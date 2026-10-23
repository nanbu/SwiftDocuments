#!/usr/bin/env python3
"""Generate fictional DOCX input for a Pages import/save interoperability fixture.

Open the output in Pages, save as a modern .pages ZIP, then use
scripts/prepare-pages-fixture.py to install the sanitized producer file.
No external Python packages are required.
"""
import argparse
from pathlib import Path
import struct
import zlib
import zipfile


def png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    pixels = b''.join(b'\0' + b''.join(bytes((40, 100, 200) if (x + y) % 2 else (230, 150, 40)) for x in range(8)) for y in range(8))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 8, 8, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')


def generate(path):
    word = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    def p(text):
        return '<w:p><w:r><w:t>' + text + '</w:t></w:r></w:p>'
    rows = [('Label', 'Value'), ('Orbit', '42'), ('Harbor', '7.5')]
    table = '<w:tbl><w:tblPr><w:tblW w:w="6000" w:type="dxa"/></w:tblPr><w:tblGrid><w:gridCol w:w="3000"/><w:gridCol w:w="3000"/></w:tblGrid>'
    for index, cells in enumerate(rows):
        table += '<w:tr>' + ('<w:trPr><w:tblHeader/></w:trPr>' if index == 0 else '')
        for text in cells:
            table += '<w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr>' + p(text) + '</w:tc>'
        table += '</w:tr>'
    table += '</w:tbl>'
    picture = '''<w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="914400" cy="914400"/><wp:docPr id="1" name="Synthetic checker" descr="Fictional checkerboard"/><wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="1" name="Synthetic checker"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="image1"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="914400" cy="914400"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'''
    body = p('Synthetic Pages fixture') + p('A😀B 日本語') + table + p('After table') + picture + p('After image')
    doc = f'<w:document xmlns:w="{word}" xmlns:r="{rel}" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>{body}<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/></w:sectPr></w:body></w:document>'
    entries = {
        '[Content_Types].xml': b'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>',
        '_rels/.rels': f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="main" Type="{rel}/officeDocument" Target="word/document.xml"/><Relationship Id="metadata" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>'.encode(),
        'word/document.xml': doc.encode(),
        'word/_rels/document.xml.rels': f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="image1" Type="{rel}/image" Target="media/checker.png"/></Relationships>'.encode(),
        'word/media/checker.png': png(),
        'docProps/core.xml': b'<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator>Sample Author</dc:creator><cp:lastModifiedBy>Sample Author</cp:lastModifiedBy></cp:coreProperties>',
    }
    with zipfile.ZipFile(path, 'w') as package:
        for name, data in sorted(entries.items()):
            entry = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0)); entry.compress_type = zipfile.ZIP_DEFLATED
            package.writestr(entry, data)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    generate(args.output)
