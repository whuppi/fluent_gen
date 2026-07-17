# Security Policy

## Reporting a vulnerability

Report privately via [GitHub Security Advisories](https://github.com/whuppi/fluent_gen/security/advisories/new). Do not open a public issue.

## What's in scope

- **Generated code diverging from the FTL** — an accessor that formats a different message than its name claims, or silently drops a required argument, ships wrong strings into every consumer with the analyzer's blessing. That's a security report.

- **Path handling in discovery** — `ftl_dir` walking must stay inside the consumer package. Discovery reading or writing outside the configured tree got past a control.

## What's NOT in scope

- **Runtime behavior** — the generated file depends on `fluent_bundle` alone; runtime concerns are [its scope](https://github.com/whuppi/fluent_bundle/blob/dev/SECURITY.md).

- **Malicious build environments** — the generator runs under `build_runner` with the consumer's own privileges; an attacker who controls the build already controls the output.
## Operational notes (known, accepted)

- **The generator executes no FTL content** — messages are parsed to data and emitted as string literals; expressions never become code.

## Response

Valid reports are fixed and shipped as patch versions.
