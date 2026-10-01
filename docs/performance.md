# Reading performance

`scan` releases each top-level body-block XML tree after its callback. It retains input ZIP bytes, expanded body XML, style information and requested related stories. A large table is one block. The returned document omits body blocks; `read` retains the complete body model. Neither operation promises constant process memory.

A preliminary local measurement used 100,000 synthetic paragraphs (4,300,000 characters, 270,029 compressed bytes), release mode, macOS 27.0 / arm64 and Apple Swift 6.4 on 2026-10-01. Three alternating scan / read pairs validated the entire block and character counts with zero warnings before accepting measurements.

| Operation | Median wall time | Median maximum RSS |
|---|---:|---:|
| `scan` | 6.94 s | 19.42 MiB |
| `read` | 7.87 s | 96.16 MiB |

Times ranged from 4.02–8.86 s for scan and 5.06–8.19 s for read. Verification builds were running during part of this preliminary measurement; these are illustrative observations, not stable comparative benchmarks or guarantees. Measure on an idle machine for meaningful comparisons. Run count, tables, images, style count and data shape affect results.

Reproduce on macOS (the script uses `/usr/bin/time -l`):

```sh
swift build -c release
python3 scripts/benchmark.py \
  --binary "$(swift build -c release --show-bin-path)/swiftdoc" \
  --paragraphs 100000 --runs 3 --output /tmp/swiftdocuments-benchmark.json
```

The Foundation SAX parser keeps body XML trees bounded to a block, warning aggregation prevents repeated warnings from accumulating, style resolution is cached and images inflate lazily. Future input-stream inflation and formatting sharing must pass the same correctness tests before adoption.
