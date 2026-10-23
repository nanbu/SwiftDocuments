#!/usr/bin/env python3
"""Sanitize a blank Pages producer document for the basic text writer.

In Pages Creator Studio 15.4 choose Basic > Blank, then File > Save As and
save a single-file ZIP as blank.pages without typing any content. Run:
    python3 scripts/prepare-pages-template.py blank.pages output.pages
No user documents or media are inputs. Keep this script with the template.
"""
import argparse
import plistlib
from pathlib import Path
import zipfile
from pages_wire import decode_iwa, encode_iwa, remove_printer, varint, fields, scalar


def prepare(source, output):
    entries = {}
    with zipfile.ZipFile(source) as archive:
        for name in archive.namelist():
            if name.endswith('/') or name.startswith(('preview', 'Data/')):
                continue
            data = archive.read(name)
            if name.endswith('.iwa'):
                decoded = decode_iwa(data)
                if name == 'Index/Document.iwa':
                    decoded = remove_printer(decoded)
                # A blank template must contain no source storage text.
                position = 0
                while position < len(decoded):
                    size, position = varint(decoded, position)
                    header = decoded[position:position + size]; position += size
                    for key, wire, info, raw in fields(header):
                        if key != 2:
                            continue
                        length = scalar(info, 3)
                        payload = decoded[position:position + length]; position += length
                        if scalar(info, 1) == 2001:
                            assert not any(k == 3 and v for k, w, v, r in fields(payload)), 'template contains text'
                data = encode_iwa(decoded)
                assert b'/Users/' not in decoded and b'/home/' not in decoded, 'local path in template'
            elif name.endswith('.plist'):
                properties = plistlib.loads(data)
                if name == 'Metadata/Properties.plist':
                    for key in properties:
                        if 'UUID' in key:
                            properties[key] = '00000000-0000-4000-8000-000000000001'
                data = plistlib.dumps(properties, fmt=plistlib.FMT_BINARY, sort_keys=True)
            elif name == 'Metadata/DocumentIdentifier':
                data = b'00000000-0000-4000-8000-000000000001'
            entries[name] = data
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w') as archive:
        for name, data in sorted(entries.items()):
            entry = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data)
    print(f'Sanitized blank Pages template: {len(entries)} parts')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    prepare(args.source, args.output)
