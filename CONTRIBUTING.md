# Contributing

SwiftDocuments is in development. Discuss API changes in an issue before submitting a large implementation. Read docs/implementation-spec.md and docs/format-design.md; keep Core format-neutral and format-specific interpretation inside codecs.

Run `swift test`, `swift build -c release`, `python3 scripts/check-contract.py` and `python3 scripts/check-public-content.py`. Build the public reference with `scripts/build-docs.sh`. Update the support ledger, relevant documentation and meaningful fixtures together when behavior changes.

Fixtures must be synthetic, with provenance and regeneration instructions. Never include customer documents, credentials, personal metadata, private work records or machine-specific paths. Do not claim a format or platform is verified without executing its relevant checks.

Use Conventional Commits. Keep API changes and their rationale reviewable; report unsupported content through warnings rather than silently discarding it.
