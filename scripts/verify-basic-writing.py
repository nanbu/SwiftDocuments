#!/usr/bin/env python3
"""Verify generated packages independently; optionally read them with LibreOffice.

Requires a built swiftdoc CLI. All source text is fictional. No producer output
is installed into the repository. Pages application verification is a separate
manual open/display check, not inferred from ZIP or self-read checks.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile
import zipfile
import xml.etree.ElementTree as ET

SOURCE = "# Fictional writing probe\n\n日本語 😀 **bold** *italic* [Link](https://example.invalid)\n\n3. Three\n4. Four\n\n```\nLiteral *code*\n```\n\nLast line  \nsecond line\n"


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swiftdoc', type=Path, default=root / '.build/release/swiftdoc')
    parser.add_argument('--soffice', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='swiftdoc-writing-') as work:
        work = Path(work)
        source = work / 'fictional.md'; source.write_text(SOURCE)
        for kind in ('docx', 'docm', 'odt', 'pages'):
            output = work / ('probe.' + kind)
            subprocess.run([str(args.swiftdoc), 'convert', str(source), str(output)], check=True, capture_output=True)
            with zipfile.ZipFile(output) as archive:
                assert archive.testzip() is None
                for name in archive.namelist():
                    if name.endswith(('.xml', '.rels')):
                        ET.fromstring(archive.read(name))
                if kind in ('docx', 'docm'):
                    main = ET.fromstring(archive.read('word/document.xml'))
                    text = ''.join(main.itertext())
                    assert '日本語 😀' in text and 'Literal *code*' in text
                    types = archive.read('[Content_Types].xml')
                    assert (b'macroEnabled' in types) == (kind == 'docm')
                    assert not any('vba' in name.lower() for name in archive.namelist())
                if kind == 'odt':
                    entry = archive.infolist()[0]
                    assert entry.filename == 'mimetype' and entry.compress_type == zipfile.ZIP_STORED
                    assert not entry.extra
                    assert archive.read('mimetype') == b'application/vnd.oasis.opendocument.text'
                if kind == 'pages':
                    assert 'Index/Document.iwa' in archive.namelist()
            if args.soffice and kind != 'pages':
                destination = work / kind; destination.mkdir()
                result = subprocess.run([str(args.soffice), '-env:UserInstallation=' + (work / 'profile').as_uri(), '--headless', '--convert-to', 'txt:Text', '--outdir', str(destination), str(output)], capture_output=True, text=True, timeout=60)
                assert result.returncode == 0, result.stderr
                text = (destination / 'probe.txt').read_text(encoding='utf-8-sig')
                assert '3. Three' in text and '4. Four' in text, (kind, text)
                assert all(value in text for value in ('Fictional writing probe', '日本語 😀', 'bold', 'italic', 'Link', 'Three', 'Four', 'Literal *code*', 'Last line', 'second line')), (kind, text)
            print(kind + ': ZIP CRC, package structure' + (' and LibreOffice text passed' if args.soffice and kind != 'pages' else ' passed'))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
