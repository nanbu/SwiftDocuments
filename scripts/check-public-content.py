#!/usr/bin/env python3
"""Audit publishable files and optional reachable Git history; includes negative controls."""
import argparse
import io
from pathlib import Path
import re
import subprocess
import sys
import zipfile

RULES = [
    ('personal home path', re.compile(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/')),
    ('private companion reference', re.compile(('SwiftDocuments' + '-Works').encode())),
    ('private key', re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----')),
    ('GitHub credential', re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})')),
]


def check_file(name, data):
    errors = []
    parts = Path(name).parts
    if any(part in ('archive', 'experiments', 'reports', 'translations') for part in parts):
        errors.append(name + ': private work directory')
    if Path(name).suffix in ('.bundle', '.pem', '.key') or Path(name).name.startswith('.env'):
        errors.append(name + ': private artifact')
    if re.search(r'benchmark-\d+.*\.json$', name):
        errors.append(name + ': raw measurement record')
    blobs = [(name, data)]
    if zipfile.is_zipfile(io.BytesIO(data)):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            blobs += [(name + ':' + entry, archive.read(entry)) for entry in archive.namelist() if not entry.endswith('/')]
    for location, blob in blobs:
        for label, rule in RULES:
            if rule.search(blob): errors.append(location + ': ' + label)
    return errors


def self_test():
    good = b'Copyright (c) 2026 Shinichi Nambu. https://github.com/nanbu/SwiftDocuments'
    if check_file('README.md', good): raise RuntimeError('valid public text was refused')
    bad = [
        ('README.md', ('/Us' + 'ers/private-owner/report').encode(), 'personal home path'),
        ('docs/spec.md', ('SwiftDocuments' + '-Works').encode(), 'private companion reference'),
        ('secret.txt', ('-----BEGIN ' + 'PRIVATE KEY-----').encode(), 'private key'),
        ('config.txt', ('gh' + 'p_' + 'a' * 36).encode(), 'GitHub credential'),
        ('config.txt', ('github_' + 'pat_' + 'a' * 36).encode(), 'GitHub credential'),
        ('archive/report.md', good, 'private work directory'),
        ('docs/translations/README.md', good, 'private work directory'),
        ('.env.local', good, 'private artifact'),
        ('original.bundle', good, 'private artifact'),
        ('docs/benchmark-100k.json', good, 'raw measurement record'),
    ]
    packed = io.BytesIO()
    with zipfile.ZipFile(packed, 'w') as archive: archive.writestr('docProps/core.xml', bad[0][1])
    bad.append(('fixture.docx', packed.getvalue(), 'personal home path'))
    for name, data, expected in bad:
        if not any(expected in result for result in check_file(name, data)):
            raise RuntimeError('negative control missed: ' + expected)
    print('Public-content negative controls: %d passed' % len(bad))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--history', action='store_true', help='also inspect every reachable revision')
    args = parser.parse_args()
    self_test()
    if args.self_test: return 0
    root = Path(__file__).resolve().parents[1]
    names = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=root).decode().split('\0')
    names = sorted(set(name for name in names if name and (root / name).is_file()))
    if not names: raise RuntimeError('empty public-file evaluation set')
    errors = []
    for name in names: errors += check_file(name, (root / name).read_bytes())
    revisions = []
    if args.history:
        revisions = subprocess.check_output(['git', 'rev-list', '--all'], cwd=root).decode().splitlines()
        if not revisions: raise RuntimeError('empty Git-history evaluation set')
        for revision in revisions:
            tracked = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', '-z', revision], cwd=root).decode().split('\0')
            for name in filter(None, tracked):
                data = subprocess.check_output(['git', 'show', revision + ':' + name], cwd=root)
                errors += [revision[:8] + ' ' + problem for problem in check_file(name, data)]
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print('Public content: %d files, %d historical revisions passed' % (len(names), len(revisions)))
    return 0


if __name__ == '__main__': sys.exit(main())
