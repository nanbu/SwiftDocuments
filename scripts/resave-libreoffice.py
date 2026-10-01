#!/usr/bin/env python3
"""Recreate the sanitized LibreOffice interoperability fixture (requires LibreOffice)."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("--soffice", default="soffice")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
fixtures = root / "Tests/SwiftDocumentsTests/Fixtures"
with tempfile.TemporaryDirectory(prefix="swiftdocuments-lo-") as directory:
    work = Path(directory)
    subprocess.run([args.soffice, "-env:UserInstallation=" + (work / "profile").as_uri(), "--headless", "--convert-to", "docx:Office Open XML Text", "--outdir", str(work), str(fixtures / "python-docx.docx")], check=True)
    with zipfile.ZipFile(work / "python-docx.docx") as src, zipfile.ZipFile(fixtures / "libreoffice.docx", "w") as dst:
        for path in src.namelist():
            data = src.read(path)
            if path == "docProps/core.xml":
                node = ET.fromstring(data)
                for child in node:
                    if child.tag.split("}")[-1] in ("creator", "lastModifiedBy"): child.text = "Sample Author"
                data = ET.tostring(node, encoding="utf-8", xml_declaration=True)
            info = zipfile.ZipInfo(path, (2026, 1, 1, 0, 0, 0)); info.compress_type = zipfile.ZIP_DEFLATED
            dst.writestr(info, data)
