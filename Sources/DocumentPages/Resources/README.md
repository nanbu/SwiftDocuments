# Blank Pages writing template

`Blank.pages` was created in Pages Creator Studio 15.4 on macOS on 2026-10-23
using Basic > Blank, with no source text or user assets. It is structural
producer data used by the basic body-text writer; it contains no user document.

Reproduce by saving a new empty single-file Pages document and running
`scripts/prepare-pages-template.py`. The script rejects nonempty text storage,
removes preview/media/printer data, normalizes document identifiers and ZIP
metadata, and independently re-encodes IWA frames. The writer preserves the
producer graph and replaces only the referenced BODY storage text and its
archive length. It does not use the template as evidence for rich-text writing.
