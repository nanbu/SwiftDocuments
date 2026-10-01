# Verification

Run from the package root. Empty evaluation sets are failures.

| Check | Command | Negative controls / boundary |
|---|---|---|
| Behavior and malformed input | `swift test` | Synthetic ZIP/XML boundary fixtures plus independent producer oracles; Core/DOCX-only linking |
| Optimized build | `swift build -c release` | All products compile |
| Support declarations | `python3 scripts/check-contract.py` | README matches nonempty support ledger, advertised tests exist, no package dependencies, synthetic fixture metadata |
| Support detector | `python3 scripts/check-contract.py --self-test` | Table drift, empty ledger, missing test, added dependency, personal fixture author |
| Public content | `python3 scripts/check-public-content.py --history` | Tracked and untracked nonignored files, ZIP contents and every reachable Git revision; home paths, companion references, keys/tokens, private directories and artifacts |
| Public detector | `python3 scripts/check-public-content.py --self-test` | Eleven positive/negative cases, including an embedded ZIP leak; always also runs before the ordinary check |
| API reference | `scripts/build-docs.sh` | Fresh library-only compiler graphs with explicit re-export inclusion, public access only, every explicit symbol is rendered, required entry points and guide pages, no local home paths in output; DocC warnings fail |
| API detector | `python3 scripts/check-api-reference.py --self-test` | Missing rendered symbol, empty graph / output and local-path leak |

CI runs behavioral, release and publication checks on macOS and Linux. DocC builds and deploys separately on macOS. Producer regeneration needs python-docx / LibreOffice, but test execution does not. iOS execution is not yet verified. Public-content checks supplement human review; they are not a general-purpose secret scanner.

The Linux Actions container trusts only its checked-out workspace for Git ownership checks. DocC queries the current module path and invokes the library symbol extractor with explicit re-export inclusion; no test-runner graph is needed.
