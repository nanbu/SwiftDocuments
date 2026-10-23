#!/usr/bin/env python3
"""Sanitize the fictional DOCX fixture after importing/saving in Pages 15.4.

Usage: python3 scripts/prepare-pages-fixture.py saved.pages output.pages
Generate input using generate-pages-source.py. In Pages open that DOCX, choose
Save, then save as a modern .pages file. Only generated checkerboard media is
distributed. Preview images and unused Apple template images are removed.
The document printer field is removed, plist UUIDs/timestamps are normalized,
and IWA chunks are independently re-encoded without changing other payloads.
"""
import argparse
import importlib.util
from pathlib import Path
import plistlib
import zipfile
from pages_wire import decode_iwa, encode_iwa, remove_printer


def prepare(source, output):
    spec = importlib.util.spec_from_file_location('pages_source', Path(__file__).with_name('generate-pages-source.py'))
    generator = importlib.util.module_from_spec(spec); spec.loader.exec_module(generator)
    checker = generator.png(); entries = {}; kept = []
    with zipfile.ZipFile(source) as package:
        for name in package.namelist():
            if name.endswith('/') or name.startswith('preview'): continue
            data = package.read(name)
            if name.startswith('Data/'):
                if data != checker: continue
                kept.append(name)
            elif name.endswith('.iwa'):
                decoded = decode_iwa(data)
                if name == 'Index/Document.iwa': decoded = remove_printer(decoded)
                if b'/Users/' in decoded or b'/home/' in decoded: raise ValueError('local path in producer graph')
                data = encode_iwa(decoded)
            elif name == 'Metadata/Properties.plist':
                properties = plistlib.loads(data)
                for key in properties:
                    if 'UUID' in key: properties[key] = '00000000-0000-4000-8000-000000000001'
                data = plistlib.dumps(properties, fmt=plistlib.FMT_BINARY, sort_keys=True)
            entries[name] = data
    if len(kept) != 1: raise ValueError('expected one fictional checkerboard asset')
    with zipfile.ZipFile(output, 'w') as package:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0)); info.compress_type = zipfile.ZIP_DEFLATED
            package.writestr(info, data)
    print('Sanitized Pages fixture: %d parts, generated media %s' % (len(entries), kept[0]))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path); parser.add_argument('output', type=Path)
    args = parser.parse_args(); prepare(args.source, args.output)
