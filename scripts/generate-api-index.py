#!/usr/bin/env python3
"""Generate an English API inventory from the current public compiler symbol graph."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'docs/api-reference.md'


def generate(graph):
    symbols = [s for s in graph['symbols'] if '::SYNTHESIZED::' not in s['identifier']['precise']]
    if not symbols:
        raise ValueError('empty public API evaluation set')
    groups = {}
    for symbol in symbols:
        path = symbol['pathComponents']
        declaration = ''.join(f['spelling'] for f in symbol.get('declarationFragments', []))
        if not declaration:
            raise ValueError('missing public declaration: ' + '.'.join(path))
        groups.setdefault(path[0], []).append((path, declaration, symbol['identifier']['precise']))
    out = ['# Public API inventory', '',
           'Generated from the current compiler symbol graph by `scripts/generate-api-index.py`.',
           'This lists explicit public declarations in DocumentCore, DocumentDOCX, DocumentODT, DocumentPages and the',
           'SwiftDocuments umbrella, including convenience extensions and enum cases.',
           'Compiler-synthesized conformances are omitted. Use the DocC reference for',
           'parameter documentation and the reading specification for support boundaries.', '',
           f'Explicit public declarations: {len(symbols)}.', '']
    for name, entries in sorted(groups.items()):
        out += ['## ' + name, '']
        for path, declaration, precise in sorted(entries, key=lambda row: (row[0], row[1], row[2])):
            out += ['```swift', declaration, '```', '']
    return '\n'.join(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('graph', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    content = generate(json.loads(args.graph.read_text()))
    if args.check:
        if not TARGET.exists() or TARGET.read_text() != content:
            raise SystemExit('Public API inventory is stale; regenerate with the current symbol graph')
        print('Public API inventory matches compiler declarations')
    else:
        TARGET.write_text(content)
        print('Generated public API inventory')


if __name__ == '__main__':
    main()
