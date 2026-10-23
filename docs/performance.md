# Reading performance

Word `scan` releases each top-level body-block XML tree after its callback. It retains input ZIP bytes, expanded body XML, style information and requested related stories. ODT retains its content XML tree; Pages retains its decoded IWA graph and constructs each text storage's blocks before delivering them. A large table or block content control is one block. The returned document omits body blocks; `read` retains the complete body model. Neither operation promises constant process memory.

Local measurements used 100,000 synthetic paragraphs and 4,300,000 characters in release mode on macOS 27.0.1 / arm64 with Apple Swift 6.4 on 2026-10-16. Each workload ran three times per operation, checking complete block/character counts and zero warnings. No verification builds ran during measurement. Time and maximum resident memory are measured together with `/usr/bin/time -l`.

The plain input had 270,029 compressed bytes. The dense input had 332,371 compressed bytes and set alignment, spacing, paragraph retention, source Latin/Japanese fonts, size, bold and language on every paragraph/run. Font names are source data; no installed fonts are consulted.

| Input | Operation | Median wall time | Observed time range | Median maximum RSS |
|---|---|---:|---:|---:|
| Plain | `scan` | 2.63 s | 2.56–3.04 s | 19.84 MiB |
| Plain | `read` | 2.49 s | 2.49–2.49 s | 54.41 MiB |
| Dense formatting | `scan` | 11.51 s | 11.32–11.78 s | 42.16 MiB |
| Dense formatting | `read` | 11.40 s | 11.34–11.54 s | 132.48 MiB |

These are local observations, not guarantees or evidence for other platforms or document shapes. Small timing differences fall within normal run-to-run variation. Tables, images, styles, revisions, equations and charts affect results; chart source trees are retained separately from the current body block. Peak RSS covers the entire process, including input, parsing and model construction.

Reproduce on macOS:

```sh
swift build -c release
python3 scripts/benchmark.py \
  --binary "$(swift build -c release --show-bin-path)/swiftdoc" \
  --paragraphs 100000 --runs 3 --output /tmp/swiftdocuments-plain.json
python3 scripts/benchmark.py \
  --binary "$(swift build -c release --show-bin-path)/swiftdoc" \
  --formatting dense --paragraphs 100000 --runs 3 \
  --output /tmp/swiftdocuments-dense.json
```

Optionally pass `--baseline /path/to/earlier/swiftdoc` to compare saved release binaries on identical bytes. The script alternates binary order between repetitions, verifies each result before accepting its measurements and reports baseline medians separately. A baseline comparison identifies the supplied local builds; it does not establish a released-version or cross-platform performance guarantee.

The Word reader's Foundation SAX parser keeps body XML trees bounded to a block. Warning aggregation limits repeated-warning storage; style resolution and prepared charts are cached per operation, and image bytes inflate lazily. Built-in dispatch reuses detected ZIP/OPC metadata. Run/paragraph formatting and sections use private copy-on-write storage; revision/history snapshots share immutable data. Original-view history reuses the decoded former properties. Selective XML lookup and text projection avoid unnecessary intermediate arrays. Value independence, namespaces, mixed content and read/scan parity are covered by regression tests. Input-stream inflation remains a future optimization.
