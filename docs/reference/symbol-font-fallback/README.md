# Symbol font fallback reference

This directory is reference material for a **separate viewer or rendering
library**. It is outside every SwiftDocuments package target and product. The
document reader/writer never depends on these files or substitutes characters.

## Ownership

SwiftDocuments preserves source text scalars, `SymbolCharacter.fontName` and
`characterCode`, run font properties, font-table charsets, numbering definitions,
level text, starts/restarts, overrides and suffixes. Applications decide how to
render those values on a machine without the source font. A document must not
be rewritten just because a font is missing on the current device.

## Display algorithm

1. Retain the original source value and formatting unchanged.
2. Establish that the character uses an explicitly specified legacy symbol font.
   Prefer the source font-table charset/encoding and explicit symbol metadata.
   Never infer an encoding merely because a scalar is in a private-use range.
3. If the source font and glyph are available, render that glyph. Some symbol
   fonts expose a byte `20...FF` through a `F020...F0FF` alias; a native adapter
   may try that alias without modifying the document.
4. Otherwise, map only a recognized legacy byte/alias using the pinned table.
   Select a Unicode-capable fallback font, with glyph-coverage checks. Names in
   `fallbackFontNames` are suggestions, not proof that any font is installed.
5. Append VS15 only for characters with a standardized text-presentation
   sequence. This requests a monochrome/text glyph and is not a glyph-coverage
   guarantee. Do not append selectors to ordinary Japanese text.
6. If no mapping or glyph exists, retain the original value and expose a display
   diagnostic. Do not silently invent a bullet or overwrite the source.

Map each list marker using the **numbering level's font**, independently from
the paragraph's text font. List-counter evaluation, shaping, ruby layout,
Japanese line breaking and pagination belong to the viewer/rendering engine.

## Reference files

- `Symbols.swift`: pure mapping API; no OS font lookup or font registration.
- `SymbolMappingData.swift`: generated tables for Adobe Symbol, Webdings and
  Wingdings 1–3, plus standardized text-presentation bases.
- `CoreTextExample.swift`: optional Apple glyph-coverage/alias example, independent
  from SwiftDocuments. It neither installs fonts nor bundles font binaries.
- `generate.py` and `data/`: offline, reproducible pinned-source generation.
- `check.swift`: independent representative checks and source-preservation checks.

Run `python3 generate.py --check`. Compile the three reference Swift files and
`check.swift` as one executable to run the representative checks. These checks
are not evidence of pixel-identical Office rendering or complete platform
glyph coverage.

## Data sources and differences from common snippets

`data/adobe-symbol.txt` is Unicode's Adobe Symbol table 1.0 (2011-07-12), with
its original notice. Multiple standard equivalents use the first listed value;
corporate private-use glyph fragments stay unmapped.

`data/wingdings-mapping.txt` transcribes section 7 of
[UTC L2/12-368 / WG2 N4384](https://www.unicode.org/wg2/docs/n4384.pdf)
(Michel Suignard, 2012-11-06). This is an encoding proposal's source-reference
table. Mapping equivalence is distinct from exact glyph contours/metrics.
In that table Wingdings `FC` maps to U+2713 (CHECK MARK), and `6C` maps to
U+26AB (MEDIUM BLACK CIRCLE). Snippets using U+2714 or U+25CF choose related
glyphs instead. Source values are retained so a renderer can make an explicit
policy choice without changing a document.

`data/text-presentation.txt` pins Unicode 17.0
[emoji-variation-sequences.txt](https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-variation-sequences.txt).
The full Unicode License v3 is in `data/UNICODE-LICENSE.txt`.

No Microsoft font files or replacement font binaries are included here.
If a viewer bundles Noto Sans Symbols 2 or another font, it must retain that
font's license and check the actual supported glyph repertoire. Apple-specific
font names must not be treated as available on Linux, Windows or Android.
