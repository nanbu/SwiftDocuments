#!/usr/bin/env python3
"""Verify rendered public symbols and guide pages, with isolated negative controls."""
import argparse
import json
from pathlib import Path
import re
import sys


def audit(symbols, rendered, blobs):
    errors = []
    if not symbols: errors.append('empty public symbol evaluation set')
    if not rendered: errors.append('empty rendered symbol evaluation set')
    missing = symbols - rendered
    if missing: errors.append('missing rendered symbols: ' + str(len(missing)))
    for path, blob in blobs:
        if re.search(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/', blob): errors.append('local path in reference: ' + path)
    return errors


def self_test():
    if audit({'symbol'}, {'symbol'}, [('page.json', b'public')]): raise RuntimeError('valid reference refused')
    controls = [
        ({'symbol'}, {'different'}, [], 'missing rendered'),
        (set(), {'symbol'}, [], 'empty public'),
        ({'symbol'}, set(), [], 'empty rendered'),
        ({'symbol'}, {'symbol'}, [('page.json', ('/Us' + 'ers/owner/code').encode())], 'local path'),
    ]
    for symbols, rendered, blobs, expected in controls:
        if not any(expected in e for e in audit(symbols, rendered, blobs)): raise RuntimeError('negative control missed: ' + expected)
    print('API-reference negative controls: 4 passed')


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('output', nargs='?'); parser.add_argument('--self-test', action='store_true'); args = parser.parse_args()
    self_test()
    if args.self_test: return 0
    if not args.output: parser.error('output directory is required')
    root = Path(__file__).resolve().parents[1]
    graph = json.loads((root / '.build/docc-public-graphs/SwiftDocuments.symbols.json').read_text())
    symbols = {s['identifier']['precise'] for s in graph['symbols'] if '::SYNTHESIZED::' not in s['identifier']['precise']}
    output = Path(args.output)
    rendered = set()
    blobs = []
    for path in output.rglob('*'):
        if not path.is_file(): continue
        data = path.read_bytes(); blobs.append((str(path.relative_to(output)), data))
        if path.suffix == '.json' and 'data' in path.parts:
            metadata = json.loads(data).get('metadata', {})
            if metadata.get('externalID'): rendered.add(metadata['externalID'])
    errors = audit(symbols, rendered, blobs)
    for guide in ('reading', 'cookbook'):
        if not (output / 'data/documentation/swiftdocuments' / (guide + '.json')).is_file(): errors.append('missing guide: ' + guide)
    if errors: print('\n'.join(errors), file=sys.stderr); return 1
    print('API reference: %d public symbols rendered; guides and privacy passed' % len(symbols))
    return 0


if __name__ == '__main__': sys.exit(main())
