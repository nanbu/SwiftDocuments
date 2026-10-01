#!/usr/bin/env python3
"""Check advertised support, test names, package dependencies and synthetic fixture metadata."""
import argparse
from pathlib import Path
import json
import re
import shutil
import sys
import tempfile
import zipfile
import xml.etree.ElementTree as ET


def check(root):
    errors = []
    try:
        ledger = json.loads((root / 'docs/support.json').read_text())
        readme = (root / 'README.md').read_text()
        table = readme.split('<!-- contract:start -->', 1)[1].split('<!-- contract:end -->', 1)[0]
        rows = [line.split('|')[1:3] for line in table.splitlines() if line.startswith('|')][2:]
        actual = [(name.strip(), state.strip()) for name, state in rows]
        expected = [(item['feature'], item['status']) for item in ledger]
        if not ledger or not actual: errors.append('empty support evaluation set')
        if actual != expected: errors.append('README support table differs from support.json')
        tests = set(re.findall(r'func\s+(\w+)\s*\(', '\n'.join(p.read_text() for p in (root / 'Tests').rglob('*.swift'))))
        if not tests: errors.append('empty test evaluation set')
        for item in ledger:
            if item['status'] != 'planned' and not item['tests']: errors.append('support has no tests: ' + item['feature'])
            for test in item['tests']:
                if test not in tests: errors.append('missing test: ' + test)
        if re.search(r'\.package\(', (root / 'Package.swift').read_text()): errors.append('external Swift package dependency')
        fixtures = [path for path in (root / 'Tests/SwiftDocumentsTests/Fixtures').iterdir() if zipfile.is_zipfile(path)]
        if not fixtures: errors.append('empty fixture evaluation set')
        for path in fixtures:
            with zipfile.ZipFile(path) as archive:
                for name in archive.namelist():
                    if not name.endswith(('.xml', '.rels')): continue
                    data = archive.read(name)
                    if re.search(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/', data): errors.append('local fixture path: ' + path.name)
                    for element in ET.fromstring(data).iter():
                        if element.tag.split('}')[-1] in ('creator', 'lastModifiedBy') and element.text not in (None, 'Sample Author', 'python-docx'):
                            errors.append('non-synthetic fixture author: ' + path.name)
    except (ValueError, KeyError, IndexError, OSError, ET.ParseError) as error:
        errors.append('malformed contract input: ' + str(error))
    return errors


def self_test(root):
    cases = [
        ('table drift', 'README.md', lambda s: s.replace('| supported |', '| planned |', 1), 'support table differs'),
        ('empty ledger', 'docs/support.json', lambda s: '[]', 'empty support'),
        ('unknown test', 'docs/support.json', lambda s: s.replace('"minimal"', '"missing_test_canary"', 1), 'missing test'),
        ('dependency', 'Package.swift', lambda s: s + '\n// .package(url: "https://example.invalid")\n', 'external Swift'),
    ]
    for label, file, mutate, expected in cases:
        with tempfile.TemporaryDirectory() as temp:
            copy = Path(temp)
            shutil.copytree(root / 'Tests', copy / 'Tests')
            shutil.copytree(root / 'docs', copy / 'docs')
            for name in ('README.md', 'Package.swift'): shutil.copy2(root / name, copy / name)
            path = copy / file; original = path.read_text(); changed = mutate(original)
            if changed == original: raise RuntimeError('negative control did not change input: ' + label)
            path.write_text(changed)
            if not any(expected in error for error in check(copy)): raise RuntimeError('negative control missed: ' + label)
    with tempfile.TemporaryDirectory() as temp:
        copy = Path(temp)
        shutil.copytree(root / 'Tests', copy / 'Tests'); shutil.copytree(root / 'docs', copy / 'docs')
        for name in ('README.md', 'Package.swift'): shutil.copy2(root / name, copy / name)
        fixture = copy / 'Tests/SwiftDocumentsTests/Fixtures/author-canary.docx'
        with zipfile.ZipFile(fixture, 'w') as archive: archive.writestr('docProps/core.xml', '<root><creator>Real Person Canary</creator></root>')
        if not any('non-synthetic' in error for error in check(copy)): raise RuntimeError('fixture author negative control missed')
    print('Support-contract negative controls: 5 passed')


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--self-test', action='store_true'); args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.self_test: self_test(root); return 0
    errors = check(root)
    if errors: print('\n'.join(errors), file=sys.stderr); return 1
    print('Support table, test references, dependencies and fixture metadata passed')
    return 0


if __name__ == '__main__': sys.exit(main())
