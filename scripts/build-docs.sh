#!/bin/bash
# Build a static DocC reference from this checkout's public API (macOS / Xcode).
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-.build/documentation}"
cmp docs/cookbook.md Sources/SwiftDocuments/SwiftDocuments.docc/Cookbook.md
# Query the current product path, then extract only library modules. Some SwiftPM
# versions attempt extraction for an unbuilt synthetic test runner, and older
# extractors omit re-exports unless explicitly allowed (SwiftPM issue #9101).
swift build --target SwiftDocuments --scratch-path .build/docc-symbols
binary_path="$(swift build --scratch-path .build/docc-symbols --show-bin-path)"
module_path="$binary_path"
if [[ -e "$binary_path/Modules/SwiftDocuments.swiftmodule" ]]; then
    module_path="$binary_path/Modules"
fi
if [[ ! -e "$module_path/SwiftDocuments.swiftmodule" ]]; then
    echo 'The current public Swift module was not produced' >&2
    exit 1
fi
graph_path="$PWD/.build/docc-library-graphs"
mkdir -p "$graph_path"
# Removing only prior generated JSON prevents stale extraction output from
# satisfying the reference checks after a toolchain change.
find "$graph_path" -name '*.symbols.json' -delete
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
for module in DocumentCore DocumentDOCX SwiftDocuments; do
    xcrun swift-symbolgraph-extract \
        -module-name "$module" \
        -target "$(uname -m)-apple-macosx14.0" \
        -sdk "$sdk_path" \
        -I "$module_path" \
        -Xcc "-fmodule-map-file=$PWD/Sources/CZlib/module.modulemap" \
        -experimental-allowed-reexported-modules=DocumentCore,DocumentDOCX \
        -minimum-access-level public \
        -omit-extension-block-symbols \
        -output-dir "$graph_path"
done
mkdir -p .build/docc-public-graphs
python3 - "$graph_path" <<'PY'
import json, sys
from pathlib import Path
source = Path(sys.argv[1]) / 'SwiftDocuments.symbols.json'
graph = json.loads(source.read_text())
assert graph['symbols'], 'empty public API evaluation set'
# Re-exported declarations do not carry their originating comments in every
# toolchain. Join by precise compiler identity, never by a short type name.
origin_comments = {}
for path in Path(sys.argv[1]).glob('*.symbols.json'):
    if path == source: continue
    for symbol in json.loads(path.read_text())['symbols']:
        if symbol.get('docComment'):
            origin_comments[symbol['identifier']['precise']] = symbol['docComment']
for symbol in graph['symbols']:
    if not symbol.get('docComment') and symbol['identifier']['precise'] in origin_comments:
        symbol['docComment'] = origin_comments[symbol['identifier']['precise']]
# The umbrella graph includes re-exported Core / DOCX declarations and its own
# convenience extensions. Omit machine paths before producing a public artifact.
for symbol in graph['symbols']:
    symbol.pop('location', None)
    symbol.pop('sourceOrigin', None)
    for line in symbol.get('docComment', {}).get('lines', []): line.pop('range', None)
    symbol.get('docComment', {}).pop('uri', None)
Path('.build/docc-public-graphs/SwiftDocuments.symbols.json').write_text(json.dumps(graph))
PY
xcrun docc convert Sources/SwiftDocuments/SwiftDocuments.docc \
    --additional-symbol-graph-dir .build/docc-public-graphs \
    --output-path "$output" \
    --fallback-bundle-identifier dev.nambu.SwiftDocuments \
    --fallback-default-module-kind Library \
    --hosting-base-path SwiftDocuments \
    --transform-for-static-hosting \
    --warnings-as-errors
python3 scripts/check-api-reference.py "$output"
cat > "$output/index.html" <<'HTML'
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="refresh" content="0;url=./documentation/swiftdocuments/"><title>SwiftDocuments API reference</title></head><body><a href="./documentation/swiftdocuments/">SwiftDocuments API reference — in development</a></body></html>
HTML
touch "$output/.nojekyll"
