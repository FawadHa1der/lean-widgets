#!/usr/bin/env python3
"""Assemble out/native-build.json from the build-native.sh logs, and the same record as the clone's own
<clone>/.lake/showcase-native-build.json (read-only over $W but for that file)."""
import json, os, subprocess, sys

SC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def env(name, default=None):
    """The same resolution as scripts/lib/env.sh: the environment, else SC/.env.local (KEY=VALUE), else default."""
    if os.environ.get(name):
        return os.environ[name]
    p = os.path.join(SC, '.env.local')
    if os.path.exists(p):
        for line in open(p):
            line = line.strip()
            if line.startswith('export '):
                line = line[7:]
            if not line or line.startswith('#') or '=' not in line:
                continue
            k, v = line.split('=', 1)
            if k == name:
                v = v.strip('"').strip("'").replace('$HOME', os.path.expanduser('~'))
                return os.path.expanduser(v) if v.startswith('~/') else v
    if default is None:
        sys.exit(f'native-report: {name} is not set (environment or {SC}/.env.local; template .env.example)')
    return default


def resolved():
    """scripts/lib/env.mjs --json: the pin-derived locations as build-native.sh resolved them (the environment or
    .env.local, then the target pin's files), so this record names the same trees as the build."""
    try:
        return json.loads(subprocess.run(['node', f'{SC}/scripts/lib/env.mjs', '--json'], capture_output=True, text=True, check=True).stdout)
    except (OSError, ValueError, subprocess.CalledProcessError) as e:
        sys.exit(f'native-report: scripts/lib/env.mjs did not answer: {e}')


def mathlib_clone(r):
    """The clone build-native.sh built in: MATHLIB_CLONE (else the target pin's clone from its lock)."""
    if not r.get('MATHLIB_CLONE'):
        sys.exit(f"native-report: MATHLIB_CLONE did not resolve: {r.get('MATHLIB_CLONE_WHY') or 'unknown reason'}")
    return r['MATHLIB_CLONE']


def kernel_build(r):
    """The kernel build build-native.sh mounted: K, the target pin's among QED64_KERNEL_BUILD, never the raw variable
    (one dir or a ':'-separated list)."""
    if not r.get('K'):
        sys.exit(f"native-report: QED64_KERNEL_BUILD did not resolve: {r.get('K_FROM') or 'unknown reason'}")
    return r['K']


W = env('QED64_SHOWCASE_WORK', os.path.expanduser('~/.cache/lean-widgets/qed64-showcase-work'))
R = resolved()
K = kernel_build(R)
IMG = env('QED64_TOOLCHAIN_IMAGE', 'qed64-toolchain:emsdk-6.0.5')
L = f'{W}/logs'


def rd(p):
    return json.load(open(p)) if os.path.exists(p) else None


def lines(p):
    return [s.strip() for s in open(p)] if os.path.exists(p) else []


steps = [json.loads(s) for s in open(f'{L}/steps.jsonl')]
for s in steps:
    nm = f"{L}/{s['step']}.new-modules.txt"
    if os.path.exists(nm):
        s['newModules'] = [m for m in lines(nm) if m]
    no = f"{L}/{s['step']}.new-oleans.txt"
    s['newOleanFiles'] = [m for m in lines(no) if m]

rep = {
    'schema': 'qed64-showcase.native-build/v1',
    'widgetsSourceHash': open(f'{W}/widgets-src/SOURCE-HASH.txt').readline().strip(),
    'clone': mathlib_clone(R),
    'toolchain': {
        'image': IMG,
        'native': '$QED64_KERNEL_BUILD/native (ro at /native)',
        'nativeCommit': open(f'{K}/native/NATIVE-COMMIT').read().strip(),
        'mathlibCommit': open(f'{K}/mathlib/MATHLIB-COMMIT').read().strip(),
        'identity': [l for l in lines(f'{L}/b1-identity.log') if l and not l.startswith(('===', '---'))],
    },
    'predicted': {
        'phase1': rd(f'{L}/delta-phase1-pre.json') and {
            k: rd(f'{L}/delta-phase1-pre.json')[k] for k in ('roots', 'counts', 'depToCompile', 'depGmp')},
        'phase2Increment': rd(f'{L}/delta-phase2-pre.json') and rd(f'{L}/delta-phase2-pre.json')['increment']['depToCompile'],
    },
    'steps': steps,
    'headerGates': {os.path.basename(p)[12:-5]: rd(f'{L}/{p}') for p in sorted(os.listdir(L))
                    if p.startswith('header-gate-') and p.endswith('.json')},
    'closurePost': rd(f'{L}/closure-post-summary.json'),
}
# out/native-build.json is the last complete `native all`'s in ANY clone; stage's N0 reads the clone's own first
# (scripts/lib/staged-tree.mjs nativeBuildFile), so a native run in another clone never revokes this clone's record
for out in (f'{SC}/out/native-build.json', os.path.join(rep['clone'], '.lake', 'showcase-native-build.json')):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(rep, open(out, 'w'), indent=1)
    open(out, 'a').write('\n')
    print('wrote', out)
