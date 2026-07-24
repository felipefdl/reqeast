# Intents Layer

Apple Shortcuts integration via App Intents. Six per-protocol actions let users run saved requests from Siri and the Shortcuts app without opening Reqeast UI.

Read [`../AGENTS.md`](../AGENTS.md) for app overview. Execution uses `Services/` Rust wrappers, not view code.

## Structure

```
Intents/
  ReqeastShortcuts.swift       # AppShortcutsProvider — registers all 6 shortcuts
  SendHttpRequestIntent.swift
  SendTcpMessageIntent.swift
  SendUdpMessageIntent.swift
  SendWebSocketMessageIntent.swift
  SendSseRequestIntent.swift
  SendGrpcRequestIntent.swift
  Entities/                    # AppEntity types for parameter pickers
  Queries/                     # EntityQuery suggestions (protocol-filtered)
  Services/
    IntentResolutionHelper.swift    # Project/request/environment resolution
    IntentExecutionService.swift    # Error types + timeout wrapper
    IntentExecutionService+Http.swift
    IntentExecutionService+Socket.swift
    IntentExecutionService+Grpc.swift
    IntentEventHandlers.swift       # Rust callback → continuation bridges
    TemplateExtractor.swift         # {{variable}} extraction
    ReqeastError+IntentMessage.swift
```

## Conventions

- One intent struct per protocol. Each conforms to `AppIntent` with `@Parameter` properties.
- Shared parameters across all intents: `project`, `request`, `environment`, `variableOverrides`, `timeout`.
- TCP/UDP/WebSocket intents add a `message` parameter. HTTP, SSE, and gRPC unary do not.
- `RequestEntityQuery` uses `@IntentParameterDependency` to filter suggestions by protocol type per intent. Do not show HTTP requests in the TCP intent picker.
- `IntentResolutionHelper` resolves project-scoped request/environment IDs and applies variable overrides. All intents call it; do not duplicate resolution logic in intent structs.
- Each intent calls its specific `IntentExecutionService` method directly. No central dispatcher.

## Execution

- `IntentExecutionService` wraps Rust services (`HttpService`, `TcpService`, `GrpcService`, etc.) with timeout via `intentWithTimeout(seconds:operation:)`.
- Timeout adds 5 seconds grace beyond the user-specified timeout before throwing `IntentExecutionError.timeout`.
- Socket protocols use `IntentEventHandlers` to bridge Rust callback interfaces to Swift continuations.
- Errors surface as `IntentExecutionError` with `CustomLocalizedStringResourceConvertible` messages. Map `ReqeastError` via `ReqeastError+IntentMessage.swift`.

## Registration

`ReqeastShortcuts` registers all six as `AppShortcut` entries with Siri phrases and SF Symbol icons. When adding a new protocol intent:

1. Create intent struct + execution extension.
2. Add `AppEntity`/`EntityQuery` if new picker types needed.
3. Register in `ReqeastShortcuts.appShortcuts`.
4. Add unit tests in `ReqeastTests/` for resolution and template extraction (no real network).

## Rules

1. Intents run headless. They must not depend on `ProjectManagerView` or session UI state.
2. Unresolved `{{variable}}` templates throw `IntentExecutionError.unresolvedVariables` before hitting Rust.
3. Deleted request/environment IDs fail with localized not-found errors, not silent fallbacks.
4. Keep intent files under ~150 lines. Shared logic belongs in `Services/`.
5. Protocol-specific terms in intent titles stay English (Shortcuts displays them as-is).