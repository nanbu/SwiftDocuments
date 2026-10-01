#!/usr/bin/env python3
"""Release read/scan benchmark. macOS: /usr/bin/time -l reports bytes and wall time together."""
import argparse
import json
import platform
import re
import statistics
import subprocess
import tempfile
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("--binary", required=True, type=Path)
parser.add_argument("--paragraphs", type=int, default=100_000)
parser.add_argument("--runs", type=int, default=3)
parser.add_argument("--output", type=Path)
args = parser.parse_args()
if platform.system() != "Darwin": parser.error("性能測定は macOS の time -l を使用します")
if args.paragraphs < 1 or args.runs < 1: parser.error("paragraphs / runs must be positive")
binary = args.binary.resolve()
with tempfile.TemporaryDirectory(prefix="swiftdocuments-bench-") as directory:
    path = Path(directory) / "large.docx"
    w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
        z.writestr("_rels/.rels", f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="main" Type="{r}/officeDocument" Target="word/document.xml"/></Relationships>')
        with z.open("word/document.xml", "w") as out:
            out.write(f'<w:document xmlns:w="{w}"><w:body>\n'.encode())
            for i in range(args.paragraphs):
                out.write(f'<w:p><w:r><w:t>Paragraph {i:06d}: SwiftDocuments benchmark.</w:t></w:r></w:p>\n'.encode())
            out.write(b'</w:body></w:document>')
    records = {"scan": [], "read": []}
    for _ in range(args.runs):
        for operation in ("scan", "read"):
            result = subprocess.run(["/usr/bin/time", "-l", str(binary), operation, str(path)], capture_output=True, text=True)
            if result.returncode: raise RuntimeError(result.stderr.strip())
            time_match = re.search(r"([\d.]+) real", result.stderr)
            rss_match = re.search(r"(\d+)\s+maximum resident set size", result.stderr)
            if not time_match or not rss_match: raise RuntimeError("time -l の測定結果を解釈できません")
            blocks = int(re.search(r"blocks=(\d+)", result.stdout).group(1))
            chars = int(re.search(r"characters=(\d+)", result.stdout).group(1))
            expected_chars = sum(len(f"Paragraph {i:06d}: SwiftDocuments benchmark.") for i in range(args.paragraphs))
            if blocks != args.paragraphs or chars != expected_chars or "warnings=0" not in result.stdout:
                raise RuntimeError("benchmark content was not fully read")
            records[operation].append({"seconds": float(time_match.group(1)), "rss_bytes": int(rss_match.group(1)), "output": result.stdout.strip()})
    report = {"platform": platform.platform(), "machine": platform.machine(), "swift": subprocess.check_output(["swift", "--version"], text=True).strip(),
        "paragraphs": args.paragraphs, "runs": args.runs, "zip_bytes": path.stat().st_size, "records": records,
        "medians": {op: {"seconds": statistics.median(x["seconds"] for x in xs), "rss_mib": round(statistics.median(x["rss_bytes"] for x in xs) / 1024**2, 2)} for op, xs in records.items()}}
    text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output: args.output.write_text(text)
    print(text)
