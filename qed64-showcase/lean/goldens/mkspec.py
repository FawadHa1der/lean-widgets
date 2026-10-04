#!/usr/bin/env python3
"""Helper used while authoring lean/examples/<pkg>.json: resolves `command`
strings to explicit 0-based LSP (line, character) — character = first
non-blank column — so specs never rely on hand-counted line numbers.
Usage (as a library): from mkspec import Locator; L = Locator('<pkg>.lean');
L.at('#hasse (Finset (Fin 3))', occurrence=0) -> (line, character)."""
class Locator:
    def __init__(self, path):
        self.lines = open(path, encoding='utf-8').read().split('\n')
    def at(self, command, occurrence=0):
        hits = [i for i, l in enumerate(self.lines) if l.lstrip().startswith(command)]
        if len(hits) <= occurrence:
            raise SystemExit(f'not found: {command!r} (#{occurrence}); hits={hits}')
        i = hits[occurrence]
        return i, len(self.lines[i]) - len(self.lines[i].lstrip())
    def cursor(self, command, expect, occurrence=0):
        l, c = self.at(command, occurrence)
        return {'line': l, 'character': c, 'command': command, 'expect': expect}


def relocate(pkg_json, pkg_lean):
    """Re-resolve every cursor/selection line after an edit of the example:
    cursors are matched in order (each after the previous one); clicks follow
    their cursor's old line number."""
    import json
    spec = json.load(open(pkg_json, encoding='utf-8'))
    lines = open(pkg_lean, encoding='utf-8').read().split('\n')
    remap, after = {}, 0
    for c in spec['cursors']:
        hits = [i for i, l in enumerate(lines) if i >= after and l.lstrip().startswith(c['command'])]
        if not hits:
            raise SystemExit(f'not found after {after}: {c["command"]!r}')
        i = hits[0]
        remap[c.get('line')] = i
        c['line'], c['character'] = i, len(lines[i]) - len(lines[i].lstrip())
        after = i + 1
    for s in spec.get('selections', []):
        i = remap[s['line']]
        s['line'], s['character'] = i, len(lines[i]) - len(lines[i].lstrip())
    for k in spec.get('clicks', []):
        k['cursorLine'] = remap[k['cursorLine']]
    json.dump(spec, open(pkg_json, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
    open(pkg_json, 'a').write('\n')
    return remap


if __name__ == '__main__':
    import sys
    if sys.argv[1] == 'relocate':
        print(relocate(sys.argv[2], sys.argv[3]))
