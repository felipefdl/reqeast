# Reqeast

Multi-platform API client (HTTP, TCP/TLS, UDP, WebSocket, SSE, gRPC) for macOS 26+, iOS 26+, and iPadOS 26+. SwiftUI UI over a Rust networking core via UniFFI. Single universal Xcode target.

## README and repo files

Root public files: `README.md` (logo, sections, footer), `LICENSE.md` (Apache-2.0 + brand notice), `CODE_OF_CONDUCT.md`, `SECURITY.md`, `CONTRIBUTING.md`. Copyright: Felipe Lima. Branding is not Apache-covered. Do not invent product version labels in docs (write present-tense facts). Do not put personal contact data, business plans, or ASC review identity in this tree.

## Requirements

- **macOS**: 26.0+ (Tahoe). No backwards compatibility.
- **iOS/iPadOS**: 26.0+
- **Xcode**: 26.4+
- **Swift**: 6.3+
- **Rust**: 1.88.0+ (edition 2024)
- **cargo-bundle-licenses**: Open source license attribution

## Latest Versions Policy

Always use the newest stable APIs. No older-pattern fallbacks.

- **SwiftUI**: macOS/iOS 26.4 APIs. Prefer new modifiers and containers over legacy approaches.
- **Swift**: 6.3+ strict concurrency, modern async/await.
- **Rust**: Edition 2024 idioms.

## Context7

Query Context7 (`resolve-library-id` + `query-docs`) before writing or modifying code that uses SwiftUI, Swift stdlib, Rust crates (reqwest, tokio, uniffi, rustls, roas, jaq-core), or third-party libraries. Do not rely on memorized signatures.

## Package Guides

Read every `AGENTS.md` from repo root down to the file you will touch. Deeper files override root on package-specific rules.

| Path | Guide |
|------|-------|
| `Reqeast/` | [`Reqeast/AGENTS.md`](Reqeast/AGENTS.md) — app target overview |
| `Reqeast/Models/` | [`Reqeast/Models/AGENTS.md`](Reqeast/Models/AGENTS.md) — stores, persistence, CloudSyncable |
| `Reqeast/Services/` | [`Reqeast/Services/AGENTS.md`](Reqeast/Services/AGENTS.md) — FFI, sync, spec pipeline, SafeFetch |
| `Reqeast/Views/` | [`Reqeast/Views/AGENTS.md`](Reqeast/Views/AGENTS.md) — SwiftUI, Liquid Glass, spec UI |
| `Reqeast/Intents/` | [`Reqeast/Intents/AGENTS.md`](Reqeast/Intents/AGENTS.md) — Apple Shortcuts |
| `rust/` | [`rust/AGENTS.md`](rust/AGENTS.md) — networking core, spec_import, UniFFI |
| `ReqeastTests/` | [`ReqeastTests/AGENTS.md`](ReqeastTests/AGENTS.md) — Swift Testing unit tests |
| `ReqeastUITests/` | [`ReqeastUITests/AGENTS.md`](ReqeastUITests/AGENTS.md) — XCTest UI automation |
| `scripts/` (screenshots) | [`scripts/SCREENSHOTS.md`](scripts/SCREENSHOTS.md) — **mandatory playbook** before any App Store screenshot work (capture/compose/validate/upload). |

**Generated, no AGENTS.md**: `ReqeastCore/` (XCFramework output). Never edit; regenerate via `just build-rust`.

## Architecture

- **UI**: SwiftUI + Liquid Glass. Swift handles UX; Rust handles networking and spec processing.
- **HTTP**: Stateless one-shot via reqwest (no event loop).
- **gRPC unary**: Synchronous `block_on` on the UniFFI caller thread (HTTP one-shot pattern).
- **gRPC streaming**: Command channel + tokio event loop with `biased` select (WebSocket/SSE pattern).
- **TCP/TLS/UDP/WS/SSE**: Command channel + tokio event loop with `biased` select.
- **Spec import**: Rust ingress/parse/normalize/fingerprint/diff/export; Swift Rule A apply, persistence, CloudKit batching.
- **iCloud sync**: CKSyncEngine, private DB, single "Reqeast" zone. Models implement `CloudSyncable`; JSON blobs in CKRecord `data`. LWW via `updatedAt`. Soft-delete with `deletedAt` + `DeletionTombstoneStore`.
- **Scale**: Users have large collections (full API specs, hundreds of requests). Sync must be proportional to **changed** items, never `queueSaveAll()` on refresh.
- **Storage**: UserDefaults (metadata + sync state), Keychain (credentials, iCloud-synced), Application Support (`sessions/`, `specs/`).

### CKSyncEngine — DO NOT REMOVE

`remote-notification` background mode is **required**. CKSyncEngine registers its own `CKDatabaseSubscription` and handles silent pushes internally. No `didReceiveRemoteNotification` handler needed in app code. Removing any of these breaks iCloud sync:

- `UIBackgroundModes: remote-notification` in `Reqeast/Info.plist`
- `aps-environment` + `com.apple.developer.icloud-services` in `Reqeast.entitlements`
- `registerForRemoteNotifications()` in `ReqeastApp.init()`
- Eager `_ = ProjectStore.shared` in `ReqeastApp.init()` (engine must exist before background-launch pushes)

## Design System (summary)

Retromodern + Liquid Glass. Full rules in [`Reqeast/Views/AGENTS.md`](Reqeast/Views/AGENTS.md).

- System accent for interactive controls. Brand blue (`BrandTheme.brand`) only for logo and paywall Subscribe.
- `.buttonStyle(.glass)` / `.glassProminent`. `.glassEffect()` for badges, not opaque `.background()`.
- Configuration pickers/menus: `.tint(.primary)`. Accent reserved for actions and selected states.
- `NavigationSplitView` sidebar layout. `.listStyle(.sidebar)`.
- Sheet dialogs: title, divider, content, divider, footer (Cancel left, action right).

## Multi-Platform

Single universal target. `#if os(macOS)` for platform-specific code.

- macOS-only: `VSplitView`, `HSplitView`, `.commands {}`, `Settings {}`, `@FocusedValue` menu bindings.
- Use `PlatformImage`, `PlatformClipboard` (Services), not raw AppKit/UIKit in views.
- Sheet fixed frames: wrap `.frame(width:height:)` in `#if os(macOS)`.
- `SourceEditorView`: macOS uses CodeEditSourceEditor; iOS uses TextEditor/UITextView with dual highlighter APIs.

## Swift Conventions

- `@State` local, `@Observable` shared, `@Bindable` for child bindings.
- Prefer async/await over Combine.
- 4-space indent. PascalCase types, camelCase properties.
- Files under ~150 lines. Split into extensions/subviews.
- Never add "No X Selected" placeholders. Auto-select first available item.
- All `TextField`/`TextEditor`/`SecureField`: `.devTextInput()`.
- Offload sync Rust FFI via `@concurrent`. Do not add new `Task.detached`.

## Rust Conventions

See [`rust/AGENTS.md`](rust/AGENTS.md). Summary: edition 2024, clippy `-D warnings`, rustfmt 120/2, ~150 lines per file, typed errors, no panics on user input across FFI.

## UniFFI

- Proc-macro mode only. No UDL. Never hand-edit `Reqeast/Services/reqeast_core.swift` or `ReqeastCore/`.
- After Rust API changes: `just build-rust`, sync bindings to `Reqeast/Services/`.

## Error Handling

Developer tool. Errors are primary UX.

- Never discard error chains (Rust → Swift → view).
- All error `Text`: `.textSelection(.enabled)`.
- Use `RequestError` everywhere. Never `String?` for errors.
- Classify precisely in Rust (`is_timeout()`, `is_connect()`, etc.) before generic buckets.
- Conversation log errors: red/destructive, not `.secondary`.

## Localization

- Catalog: `Reqeast/Localizable.xcstrings`. Dev language: `en`.
- Languages: en, zh-Hans, zh-Hant, ja, fr, pt-BR, es, ko, de. **All 9 required** for new user-facing strings.
- SwiftUI literals in `Text()`/`Button()` auto-localize. Computed `String` and helper params: `String(localized:)`.
- Enums displayed in UI: `.localizedName`, not `.rawValue`.
- **Natural phrasing, not literal loans.** Translate meaning, not English jargon. Internal code may say `snapshot`; user-facing copy describes behavior (imported spec, unlinked import, one-time import). Never transliterate English terms (e.g. snapshot → instantâneo, スナップショット) unless the locale already uses that word in everyday UI.
- Protocol and product names stay untranslated: HTTP methods, headers, TCP/UDP, OpenAPI, Postman, GitHub, Keychain, iCloud.
- Pluralization: String Catalog variants, not manual ternaries.
- Batch scripts under `scripts/add_*_i18n.py`: use merge mode for backfills; put corrections in `FIXUPS` so re-runs stay idempotent.
- Audit pass: `python3 scripts/fix_i18n_natural_phrasing.py` applies reviewed phrasing fixes (overwrites). Re-run after changing `add_*_i18n.py` FIXUPS if they overlap.

## Building

```sh
just build-rust          # Rust XCFramework + UniFFI bindings
just test-all            # Rust + Swift macOS unit tests
just test-ui             # UI tests (macOS; skips ScreenshotTests)
just test-ui-screenshots # Marketing screenshot UITests only (opt-in)
just screenshots         # Capture + compose App Store shots (see scripts/SCREENSHOTS.md)
just deliver-screenshots # Upload screenshots to ASC (iOS + Mac)
just test-swift-ios      # Swift unit tests on iOS Simulator
just build-ios-sim       # Build for iOS Simulator
just lint-rust           # clippy -D warnings
just generate-licenses   # licenses.json from Rust deps
just rebuild             # Full clean + build
```

Spec import extras: `just update-spec-goldens`, `just update-spec-project-goldens`, `just test-spec-perf` (opt-in), `just test-ckasset-harness` (opt-in).

Manual: `cd rust && ./build-xcframework.sh`, then build in Xcode.

## Marketing screenshots — never fight the image

**Playbook:** [`scripts/SCREENSHOTS.md`](scripts/SCREENSHOTS.md) (read before any screenshot work). Scripts encode the rules.

| Final use | Simulator | Raw dir |
|-----------|-----------|---------|
| iPad App Store 01–03 | `iPad Pro 13-inch (M5)` | `raw/ipad/` (~1.33) |
| Multi collage iPad bezel (Mac/iPhone **03**) | `iPad Pro 11-inch (M5)` | `raw/ipad11/` (~1.45) |
| iPhone | `iPhone 17 Pro Max` | `raw/iphone/` |
| Mac | normal WindowGroup chrome (`references/mac-1.png`) | `raw/mac/` |

- **Recapture** on the correct sim. Do **not** stretch/crop/non-uniform-scale wrong-device raws into a plate.
- No **Ready for Apple Intelligence** CFU banner. Clear via `prepare_sim_for_marketing` + re-capture; never paint the PNG.
- Demo sidebars (Mac / iPad / iPad11 `01`): Weather, Stripe, Chat, IoT visible. Empty white list = re-capture with 8s settle.
- Partial: `LANGS=en DEVICES=ipad11,iphone bash scripts/capture-screenshots.sh`
- Gate: `just screenshots-validate` (also auto after capture / before compose).

## StoreKit

- Product ID: `com.reqeast.app.yearly.v1` (yearly auto-renewable).
- App always fully functional. Subscription optional (Sublime Text model). No feature gating.
- Paywall only on explicit support button tap. "Not Now" always visible.
- StoreKit 2: `Product.products(for:)`, `Transaction.updates`, `Transaction.currentEntitlements(for:)`.

## Apple Shortcuts

Six per-protocol intents. See [`Reqeast/Intents/AGENTS.md`](Reqeast/Intents/AGENTS.md).

## Testing

| Target | Framework | Guide |
|--------|-----------|-------|
| `ReqeastTests` | Swift Testing | [`ReqeastTests/AGENTS.md`](ReqeastTests/AGENTS.md) |
| `ReqeastUITests` | XCTest | [`ReqeastUITests/AGENTS.md`](ReqeastUITests/AGENTS.md) |
| `rust` | cargo test | [`rust/AGENTS.md`](rust/AGENTS.md) |

Always `TZ=UTC`. UI tests require `-parallel-testing-enabled NO`.

## Copywriting

- No em dashes or double dashes as punctuation.
- No marketing cliches ("seamless", "blazing fast", "game changer").
- Direct tone. Short sentences. No AI-generated parallel structures.

## Business

- App Store (macOS + iOS/iPadOS). Free download, optional $12/year subscription.
- EULA: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
- Include EULA link in App Store metadata when Apple requires legal links.