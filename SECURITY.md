# Security

Untrusted documents are parsed without executing macros or fetching external relationships. Package and XML limits are configurable, and DTD / entity declarations are rejected. Limits bound parts and parser work; they are not a process memory budget. Use caller-managed isolation and budgets appropriate to your application.

Report vulnerabilities privately through [GitHub private vulnerability reporting](https://github.com/nanbu/SwiftDocuments/security/advisories/new). Include a minimal synthetic reproduction, expected behavior and the Swift / OS versions. Avoid posting exploitable documents in a public issue while a report is being investigated.

This project is in development and has no stable release or guaranteed security-response timeline yet.
