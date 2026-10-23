# SwiftDocuments

- `docs/implementation-spec.md` is the canonical API and reading contract. Update the specification before implementing behavior changes.
- Keep the common model in DocumentCore and Word-specific interpretation in DocumentDOCX. Do not use Word XML names for shared APIs.
- Warn about unsupported elements. Never turn a reading failure into success or an empty document, or weaken tests to make them pass.
- Add specification-based tests for new reading behavior. Run `swift test` and `swift build -c release` as the baseline checks.
- Producer fixtures must contain fictional content only. Retain their generation scripts and provenance.
- Run `scripts/check-contract.py` to detect differences between the README support table and implementation evidence.
- Report time and memory for the same performance operation. Do not claim support for unmeasured environments or behavior.
- Keep public documentation in English. Exclude private development logs, reports, credentials and machine-specific configuration.
- Publish or release only when requested. Use Conventional Commits.
