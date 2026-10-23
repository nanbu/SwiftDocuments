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
parser.add_argument("--formatting", choices=("plain", "dense"), default="plain")
parser.add_argument("--baseline", type=Path, help="optional release binary; alternate order on the same input")
args = parser.parse_args()
if platform.system() != "Darwin": parser.error("measurement requires macOS time -l")
if args.paragraphs < 1 or args.runs < 1: parser.error("paragraphs / runs must be positive")
binary = args.binary.resolve()
baseline = args.baseline.resolve() if args.baseline else None
paragraph_properties = '<w:pPr><w:jc w:val="left"/><w:spacing w:before="120" w:after="120"/><w:keepNext/></w:pPr>' if args.formatting == "dense" else ''
run_properties = '<w:rPr><w:rFonts w:ascii="Source Font" w:eastAsia="Source Japanese"/><w:sz w:val="24"/><w:b/><w:lang w:val="en-US" w:eastAsia="ja-JP"/></w:rPr>' if args.formatting == "dense" else ''
with tempfile.TemporaryDirectory(prefix="swiftdocuments-bench-") as directory:
    path = Path(directory) / "large.docx"
    w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    expected_chars = 0
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
        z.writestr("_rels/.rels", f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="main" Type="{r}/officeDocument" Target="word/document.xml"/></Relationships>')
        with z.open("word/document.xml", "w") as out:
            out.write(f'<w:document xmlns:w="{w}"><w:body>\n'.encode())
            for i in range(args.paragraphs):
                text = f"Paragraph {i:06d}: SwiftDocuments benchmark."
                expected_chars += len(text)
                out.write(f'<w:p>{paragraph_properties}<w:r>{run_properties}<w:t>{text}</w:t></w:r></w:p>\n'.encode())
            out.write(b'</w:body></w:document>')
    records = {name: {"scan": [], "read": []} for name in (["current", "baseline"] if baseline else ["current"])}
    for iteration in range(args.runs):
        for operation in ("scan", "read"):
            order = list(records) if iteration % 2 == 0 else list(reversed(records))
            for name in order:
                executable = binary if name == "current" else baseline
                result = subprocess.run(["/usr/bin/time", "-l", str(executable), operation, str(path)], capture_output=True, text=True)
                if result.returncode: raise RuntimeError(result.stderr.strip())
                time_match = re.search(r"([\d.]+) real", result.stderr)
                rss_match = re.search(r"(\d+)\s+maximum resident set size", result.stderr)
                if not time_match or not rss_match: raise RuntimeError("could not interpret time -l measurements")
                counts = {key: re.search(rf"\b{key}=(\d+)\b", result.stdout) for key in ("blocks", "characters", "warnings")}
                if not all(counts.values()) or int(counts["blocks"][1]) != args.paragraphs or int(counts["characters"][1]) != expected_chars or int(counts["warnings"][1]) != 0:
                    raise RuntimeError("benchmark content was not fully read with zero warnings")
                records[name][operation].append({"seconds": float(time_match.group(1)), "rss_bytes": int(rss_match.group(1)), "output": result.stdout.strip()})
    def medians(values):
        return {op: {"seconds": statistics.median(x["seconds"] for x in xs), "rss_mib": round(statistics.median(x["rss_bytes"] for x in xs) / 1024**2, 2)} for op, xs in values.items()}
    report = {"platform": platform.platform(), "machine": platform.machine(), "swift": subprocess.check_output(["swift", "--version"], text=True).strip(),
        "paragraphs": args.paragraphs, "characters": expected_chars, "formatting": args.formatting, "runs": args.runs, "zip_bytes": path.stat().st_size,
        "records": records["current"], "medians": medians(records["current"])}
    if baseline: report["baseline"] = {"records": records["baseline"], "medians": medians(records["baseline"])}
    text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output: args.output.write_text(text)
    print(text)
