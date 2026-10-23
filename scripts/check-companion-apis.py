#!/usr/bin/env python3
"""Build and run local two-package consumers; no checkout mutation or network dependencies."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def check(root, companion, name, core, model, formats):
    manifests = [root / 'Package.swift', companion / 'Package.swift']
    versions = []
    for manifest in manifests:
        match = re.search(r'swift-tools-version:\s*(\d+)\.(\d+)', manifest.read_text())
        if not match:
            raise ValueError('missing Swift tools version: ' + str(manifest))
        versions.append(tuple(map(int, match.groups())))
    tools = '.'.join(map(str, max(versions)))
    work = root / '.build/companion-api-check'
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='consumer-', dir=work) as directory:
        probe = Path(directory)
        source = probe / 'Sources/Smoke'
        source.mkdir(parents=True)
        (probe / 'Package.swift').write_text(f'''// swift-tools-version: {tools}
import PackageDescription
let package = Package(name: "DocumentCompanionSmoke", platforms: [.macOS(.v14)], dependencies: [
    .package(path: {json.dumps(str(root), ensure_ascii=False)}), .package(path: {json.dumps(str(companion), ensure_ascii=False)})
], targets: [.executableTarget(name: "Smoke", dependencies: [
    .product(name: "SwiftDocuments", package: "SwiftDocuments"),
    .product(name: "{name}", package: "{name}")
])])
''')
        (source / 'main.swift').write_text(f'''import Foundation
import SwiftDocuments
import DocumentCore
import {name}
import {core}

func smoke() throws {{
    let documentCodecs = DocumentCore.CodecSet([.docx, .docm])
    let companionCodecs = {core}.CodecSet([{', '.join('.' + f for f in formats)}])
    precondition(documentCodecs.formats == [.docx, .docm])
    precondition(companionCodecs.formats.count == {len(formats)})
    let selectedDocument = try documentCodecs.codec(for: .docx)
    let selectedCompanion = try companionCodecs.codec(for: .{formats[0]})
    precondition(selectedDocument.format == .docx)
    precondition(selectedCompanion.format == .{formats[0]})
    let options = DocumentCore.ReadOptions(includeRelatedStories: false)
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let opened = try documentCodecs.read(contentsOf: url, format: .docx, options: options)
    precondition(opened.document.sourceFormat == .docx)
    precondition(opened.warnings == opened.document.readWarnings)
    let summary = try Document.inspect(contentsOf: url, format: .docx)
    precondition(summary.format == .docx)
    var count = 0
    let scan = try Document.scan(contentsOf: url, format: .docx, options: options) {{ _ in count += 1 }}
    precondition(count == opened.document.blocks.count && scan.blocksRead == count)
    let companion = {core}.{model}()
    let encoded = try companionCodecs.write(companion, as: .{formats[0]})
    let decoded = try companionCodecs.read(encoded.data, format: .{formats[0]}, options: {core}.ReadOptions())
    let companionSummary = try companionCodecs.inspect(encoded.data)
    precondition(companionSummary.format == .{formats[0]})
    _ = decoded.{model.lower()}.readWarnings
    print("SwiftDocuments + {name}: qualified APIs, registration and read / inspect / scan passed")
}}
try smoke()
''')
        env = os.environ.copy()
        env['CLANG_MODULE_CACHE_PATH'] = str(work / 'module-cache')
        env['SWIFTPM_MODULECACHE_OVERRIDE'] = str(work / 'module-cache')
        command = ['swift', 'run', '--package-path', str(probe), '--disable-sandbox',
                   '--cache-path', str(work / 'cache'), '--config-path', str(work / 'config'),
                   '--security-path', str(work / 'security'), 'Smoke',
                   str(root / 'Tests/SwiftDocumentsTests/Fixtures/minimal.docx')]
        log = work / (name.lower() + '.log')
        with log.open('w') as output:
            result = subprocess.run(command, cwd=root, env=env, stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            print(log.read_text(), file=sys.stderr)
            raise RuntimeError('companion API consumer failed: ' + name)
        print(log.read_text().splitlines()[-1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sheets', type=Path, help='local SwiftSheets checkout')
    parser.add_argument('--slides', type=Path, help='local SwiftSlides checkout')
    args = parser.parse_args()
    if not args.sheets and not args.slides:
        parser.error('at least one companion checkout is required')
    root = Path(__file__).resolve().parents[1]
    for path, name, core, model, formats in [
        (args.sheets, 'SwiftSheets', 'SheetCore', 'Workbook', ['xlsx', 'xlsm']),
        (args.slides, 'SwiftSlides', 'SlideCore', 'Presentation', ['pptx', 'pptm'])
    ]:
        if path:
            check(root, path.resolve(), name, core, model, formats)
    return 0


if __name__ == '__main__':
    sys.exit(main())
