#!/usr/bin/env python3
"""Compute the native64 compile delta for the widget packages (read-only).

Walks the import closure of the given widget library roots over:
  * the cloned Mathlib workspace (Mathlib + .lake/packages/*),
  * the exported widget sources (work/widgets-src/<pkg>),
  * the native core library (Init/Lean/Std/Lake: oleans only, never descended).
Every non-widget, non-core module in the closure is classified by the olean the
clone already holds: native (flags byte 0, empty githash), gmp (official
toolchain barrel olean), or missing. "To compile" = gmp + missing.

usage: delta.py --clone W/mathlib4 --widgets W/widgets-src --core K/native/stage1/lib/lean
                [--roots ChartKit,ExprXRay,...] [--base-roots ...] [--json out.json]
With --base-roots, modules already in the closure of the base roots are reported
separately (phase-2 increment = closure(roots) - closure(base-roots)).
"""
import argparse, json, os, re, sys

PKG_DIRS = {  # top-level module root -> package dir inside the clone
    'Mathlib': '', 'Batteries': '.lake/packages/batteries', 'ProofWidgets': '.lake/packages/proofwidgets',
    'Aesop': '.lake/packages/aesop', 'Qq': '.lake/packages/Qq', 'Plausible': '.lake/packages/plausible',
    'ImportGraph': '.lake/packages/importGraph', 'LeanSearchClient': '.lake/packages/LeanSearchClient',
    'Cli': '.lake/packages/Cli',
}
WIDGETS = {  # widget lib root -> package dir in widgets-src (the lean_lib srcDir)
    'ChartKit': 'chart-kit', 'ExprXRay': 'expr-xray', 'GraphScope': 'graph-scope', 'HasseView': 'hasse-view',
    'IntervalInspector': 'interval-inspector', 'SimpLens': 'simp-lens', 'TreeScope': 'tree-scope',
    'DistLens': 'dist-lens', 'LeanWidgetKit': 'lean-widget-kit',
}
CORE = ('Init', 'Lean', 'Std', 'Lake')


def strip(s):
    """Remove line comments and (nested) block comments, as Lean's lexer does."""
    out, i, n, depth = [], 0, len(s), 0
    while i < n:
        if s.startswith('/-', i):
            depth += 1; i += 2; continue
        if depth and s.startswith('-/', i):
            depth -= 1; i += 2
            if not depth:
                out.append(' ')
            continue
        if depth:
            i += 1; continue
        if s.startswith('--', i):
            j = s.find('\n', i)
            i = n if j < 0 else j
            continue
        out.append(s[i]); i += 1
    return ''.join(out)


def header_imports(path):
    toks = strip(open(path, encoding='utf-8').read()).split()
    out, i = [], 0
    while i < len(toks):
        t = toks[i]
        if t in ('module', 'prelude', 'public', 'meta', 'private'):
            i += 1; continue
        if t == 'import':
            i += 1
            if toks[i] == 'all':
                i += 1
            out.append(toks[i].replace('«', '').replace('»', '')); i += 1; continue
        break
    return out


def olean_class(p):
    if not os.path.exists(p):
        return 'missing'
    with open(p, 'rb') as f:
        h = f.read(80)
    if h[:5] != b'olean':
        return 'bad-magic'
    if h[6] != 0:
        return 'gmp'
    if any(h[40:80]):
        return 'githash'
    return 'native'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--clone', required=True)
    ap.add_argument('--widgets', required=True)
    ap.add_argument('--core', required=True)
    ap.add_argument('--roots', default='ChartKit,ExprXRay,GraphScope,HasseView,IntervalInspector,SimpLens,TreeScope')
    ap.add_argument('--base-roots', default='')
    ap.add_argument('--json')
    a = ap.parse_args()

    def src(m):
        top = m.split('.')[0]
        parts = m.split('.')
        if top in WIDGETS:
            return os.path.join(a.widgets, WIDGETS[top], *parts) + '.lean'
        if top in PKG_DIRS:
            return os.path.join(a.clone, PKG_DIRS[top], *parts) + '.lean'
        return None

    def olean(m):
        top = m.split('.')[0]
        parts = m.split('.')
        if top in CORE:
            return os.path.join(a.core, *parts) + '.olean'
        if top in WIDGETS:
            return os.path.join(a.clone, '.lake/build/lib/lean', *parts) + '.olean'
        return os.path.join(a.clone, PKG_DIRS[top], '.lake/build/lib/lean', *parts) + '.olean'

    edges = {}

    def closure(roots):
        seen, st = set(), list(roots)
        while st:
            m = st.pop()
            if m in seen:
                continue
            seen.add(m)
            if m.split('.')[0] in CORE:
                continue
            p = src(m)
            if p is None or not os.path.exists(p):
                raise SystemExit(f'no source for {m} ({p})')
            edges[m] = header_imports(p)
            st += [i for i in edges[m] if i not in seen]
        return seen

    roots = [r for r in a.roots.split(',') if r]
    base = [r for r in a.base_roots.split(',') if r]
    cl = closure(roots)
    bcl = closure(base) if base else set()

    def topo(mods):  # dependencies first
        order, done = [], set()
        def visit(m):
            if m in done:
                return
            done.add(m)
            for d in edges.get(m, []):
                if d in mods:
                    visit(d)
            order.append(m)
        sys.setrecursionlimit(100000)
        for m in sorted(mods):
            visit(m)
        return order

    rep = {'roots': roots, 'baseRoots': base, 'closure': len(cl)}
    cls = {}
    for m in cl:
        top = m.split('.')[0]
        kind = 'core' if top in CORE else ('widget' if top in WIDGETS else 'dep')
        cls[m] = (kind, olean_class(olean(m)))
    core_missing = sorted(m for m, (k, c) in cls.items() if k == 'core' and c != 'native')
    deps = {m: c for m, (k, c) in cls.items() if k == 'dep'}
    to_compile = [m for m in topo(set(m for m, c in deps.items() if c != 'native'))]
    rep['counts'] = {
        'core': sum(1 for k, _ in cls.values() if k == 'core'),
        'widgetOwn': sum(1 for k, _ in cls.values() if k == 'widget'),
        'depNative': sum(1 for c in deps.values() if c == 'native'),
        'depGmp': sum(1 for c in deps.values() if c == 'gmp'),
        'depMissing': sum(1 for c in deps.values() if c == 'missing'),
        'depOther': sum(1 for c in deps.values() if c not in ('native', 'gmp', 'missing')),
    }
    rep['coreNotNative'] = core_missing
    rep['depToCompile'] = to_compile
    rep['depGmp'] = sorted(m for m, c in deps.items() if c == 'gmp')
    rep['depNative'] = sorted(m for m, c in deps.items() if c == 'native')
    rep['closureModules'] = sorted(cl)
    rep['oleanClass'] = {m: c for m, (k, c) in sorted(cls.items())}
    rep['widgetOwn'] = topo(set(m for m, (k, _) in cls.items() if k == 'widget'))
    if base:
        rep['increment'] = {
            'depToCompile': [m for m in to_compile if m not in bcl],
            'depNativeNew': sorted(m for m, c in deps.items() if c == 'native' and m not in bcl),
            'widgetOwn': [m for m in rep['widgetOwn'] if m not in bcl],
        }
    # Lake builds a lean_lib's root closure only; note package files outside it.
    unbuilt = {}
    for r in roots:
        pdir = os.path.join(a.widgets, WIDGETS[r])
        for dp, dn, fn in os.walk(os.path.join(pdir, r)):
            for f in fn:
                if f.endswith('.lean'):
                    mod = os.path.relpath(os.path.join(dp, f), pdir)[:-5].replace(os.sep, '.')
                    if mod not in cl:
                        unbuilt.setdefault(r, []).append(mod)
    rep['libFilesOutsideRootClosure'] = unbuilt
    out = json.dumps(rep, indent=1)
    if a.json:
        open(a.json, 'w').write(out + '\n')
    print(json.dumps({k: rep[k] for k in ('roots', 'closure', 'counts', 'coreNotNative')}, indent=1))
    print('depToCompile', len(to_compile))
    for m in to_compile:
        print('  ', m, deps[m])
    if base:
        print('increment depToCompile', len(rep['increment']['depToCompile']),
              'depNativeNew', len(rep['increment']['depNativeNew']), 'widgetOwn', len(rep['increment']['widgetOwn']))
    if unbuilt:
        print('lib files outside root closure:', unbuilt)


if __name__ == '__main__':
    main()
