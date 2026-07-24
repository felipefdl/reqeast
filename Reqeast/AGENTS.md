# Reqeast App Target

Multi-platform API client (HTTP, TCP/TLS, UDP, WebSocket, SSE, gRPC) for macOS 26+, iOS 26+, and iPadOS 26+. SwiftUI UI over a Rust networking core via UniFFI.

Read [`../AGENTS.md`](../AGENTS.md) at the repo root for cross-cutting architecture, build commands, localization, and testing.

## Layer Guides

| Layer | Guide | Responsibility |
|-------|-------|----------------|
| Models | [`Models/AGENTS.md`](Models/AGENTS.md) | Data models, `ProjectStore`, session stores, `RequestError` |
| Services | [`Services/AGENTS.md`](Services/AGENTS.md) | Rust FFI wrappers, sync, import/export, platform helpers |
| Views | [`Views/AGENTS.md`](Views/AGENTS.md) | SwiftUI UI, Liquid Glass, navigation, protocol editors |
| Intents | [`Intents/AGENTS.md`](Intents/AGENTS.md) | Apple Shortcuts intents, entity queries, execution |

## Entry Points

| File | Role |
|------|------|
| `ReqeastApp.swift` | `@main` app, menus, shortcuts, Settings (macOS), remote notification registration, eager `ProjectStore.shared` for CKSyncEngine |
| `ContentView.swift` | Wraps `ProjectManagerView` with macOS min frame |
| `Localizable.xcstrings` | String catalog (9 languages) |

## Directory Layout

```
Reqeast/
  ReqeastApp.swift, ContentView.swift
  Models/       # @Observable stores, Codable models
  Services/     # Networking, sync, reqeast_core.swift (generated)
  Views/        # All SwiftUI
  Design/       # Themes, input modifiers, platform helpers
  Intents/      # Shortcuts (see below)
  Resources/    # licenses.json
```

## Architecture

- **UI**: SwiftUI + Liquid Glass. System accent for interactive controls.
- **State**: `@Observable` stores, `@State` local state, `@Bindable` for child bindings.
- **Networking**: Rust via UniFFI. Offload sync FFI with `@concurrent`, not `Task.detached`.
- **Sync**: `CloudSyncService` + CKSyncEngine. Remote-notification mode and entitlements are required.
- **Storage**: UserDefaults (metadata), Keychain (credentials), Application Support (sessions).

## Intents Folder

Six per-protocol Shortcuts registered in `ReqeastShortcuts.swift`:

- `SendHttpRequestIntent`, `SendTcpMessageIntent`, `SendUdpMessageIntent`, `SendWebSocketMessageIntent`, `SendSseRequestIntent`, `SendGrpcRequestIntent`
- `Entities/` and `Queries/` for AppEntity pickers (`RequestEntityQuery` filters by protocol)
- `Services/IntentResolutionHelper` + `IntentExecutionService` for shared resolution and execution

Intents call `IntentExecutionService` directly. They do not duplicate view logic.

## Multi-Platform

Single universal target. Use `#if os(macOS)` for platform code. `PlatformImage` and `PlatformClipboard` in Services, not AppKit/UIKit in views.

## Conventions

- Swift 6.3+ / SwiftUI on macOS/iOS 26+. No older API fallbacks.
- Files under ~150 lines. New strings need all 9 localizations.
- Errors: `RequestError` + `.textSelection(.enabled)`. Text fields: `.devTextInput()`.
- Use Context7 to verify API signatures before implementing.

## Building

```sh
just build-rust    # Rust XCFramework + UniFFI bindings
just test-all      # Rust + Swift unit tests
```