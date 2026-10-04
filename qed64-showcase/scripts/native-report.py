#!/usr/bin/env python3
"""Assemble out/native-build.json from the build-native.sh logs (read-only over $W)."""
import json, os, sys

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


W = env('QED64_SHOWCASE_WORK', os.path.expanduser('~/.cache/lean-widgets/qed64-showcase-work'))
K = env('QED64_KERNEL_BUILD')
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
    'clone': f'{W}/mathlib4',
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
out = f'{SC}/out/native-build.json'
json.dump(rep, open(out, 'w'), indent=1)
open(out, 'a').write('\n')
print('wrote', out)
