# Contributing

## Before you start

1. Read the root [README](README.md) for build prerequisites.
2. Read every `AGENTS.md` from the repo root down to the path you will change. Deeper files override the root.
3. Keep secrets out of commits: no API keys, no App Store review personal data, no `.env` files.

## Development setup

```sh
# Rust XCFramework + UniFFI bindings
just build-rust

# Open the Xcode project
open Reqeast.xcodeproj
```

Requirements: Xcode 26.4+, Rust 1.88.0+, `just`, `cargo-bundle-licenses`.

## Tests

Always run with `TZ=UTC`.

```sh
just test-rust
just test-swift
just test-all
just lint-rust
```

UI tests (macOS):

```sh
just test-ui
```

## Pull requests

- Prefer a focused branch and a short, human-readable PR title (not `type(scope):`).
- Explain why the change exists. Link an issue when there is one.
- Do not invent product version labels (`v1`, `v2`, "current release") in docs or user-facing copy. Write present-tense facts.
- User-facing strings: update `Reqeast/Localizable.xcstrings` for all required languages (see root `AGENTS.md`).

## Code of conduct

Participation follows [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Security

Report vulnerabilities privately: [SECURITY.md](SECURITY.md).
