#!/bin/bash
# Build a static DocC reference from this checkout's public API (macOS / Xcode).
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-.build/documentation}"
cmp docs/cookbook.md Sources/SwiftDocuments/SwiftDocuments.docc/Cookbook.md
# Swift 6.4 uses a new symbolgraph path. Extract into a fresh scratch directory
# and read its emitted location instead of accidentally using an older build.
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
swift package --scratch-path .build/docc-symbols dump-symbol-graph 2>&1 | tee "$log"
graph_path="$(sed -n 's/^Files written to //p' "$log" | tail -1)"
if [[ -z "$graph_path" || ! -f "$graph_path/SwiftDocuments.symbols.json" ]]; then
    echo 'Public umbrella symbol graph was not produced' >&2
    exit 1
fi
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
