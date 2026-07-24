# Views Layer

SwiftUI UI for Reqeast across macOS, iOS, and iPadOS. Views bind to `@Observable` stores (`ProjectStore`, session stores via `SessionRegistry`) and call into `Services/` for networking, import/export, and sync. Read [`../../AGENTS.md`](../../AGENTS.md) for global localization and error-handling rules; this file has the full Liquid Glass design system.

## Design System (Liquid Glass)

Reqeast uses a **Retromodern** aesthetic with **Liquid Glass** guidelines. Views must follow these patterns consistently.

### Buttons and Actions

- Primary actions: `.buttonStyle(.glassProminent)` (Import, Send, Done, Apply, Export).
- Secondary actions: `.buttonStyle(.glass)` (Choose File, toolbar icon buttons, compact tab buttons).
- Reserve system accent color for actions and selected states. Do not tint configuration pickers with accent.

### Pickers and Menus

- Segmented pickers, dropdown `Picker`, and configuration `Menu` controls: always `.tint(.primary)` so they render in neutral text color.
- Examples: `SpecSyncReviewSheet` segment picker, `SpecExportReviewSheet`, `MessageSettingsButton`, `GitOAuthSettingsSection`, `ImportSheet` / `ImportBundleSheet` format pickers.

### Badges and Status Bars

- Use `.glassEffect(.regular.tint(color), in: .capsule)` for badges/tags, not opaque `.background()`.
- Pair tinted glass badges with `.foregroundStyle(.white)` for contrast (`RequestMethodBadge`).
- **`SpecStatusToolbarBadge` is icon-only** in the request-list toolbar (`.primaryAction`, grouped before the add-request menu on macOS and iOS). Toolbar space is too tight for text. Use `link`, `doc.text`, or `clock.badge.exclamationmark`; put localized state in `accessibilityLabel` / `accessibilityValue` only.
- Status/info bars: lower tint opacity (~0.3) so glass tint is visible but not overpowering.
- Avoid custom backgrounds on navigation chrome. Prefer `.glassEffect()` over `.background()` for colored bars.

### Scroll Edge Effects

Apply `.scrollEdgeEffectStyle` on protocol request views so content fades under fixed connection/URL bars:

| Protocol | Modifier |
|----------|----------|
| HTTP | `.scrollEdgeEffectStyle(.soft, for: .all)` — bidirectional scroll |
| TCP, UDP, WebSocket, SSE, gRPC | `.scrollEdgeEffectStyle(.soft, for: .top)` |

### Lists and Navigation Chrome

- Sidebar lists: `.listStyle(.sidebar)`.
- Standard toolbar APIs only. No custom nav backgrounds.

### Sheet Dialog Layout

Multi-step sheets (SpecImport, SpecSync, SpecExport, Export, Import) share a chrome pattern:

**macOS** — fixed frame inside `#if os(macOS)`:

```
VStack(spacing: 0)
  header (title)
  Divider
  ScrollView { content }
  Divider
  footer (Cancel left, action right)
```

**iOS/iPadOS** — `NavigationStack` with `.toolbarTitleDisplayMode(.inline)`; Cancel/confirm in toolbar placements (`.cancellationAction`, `.confirmationAction`).

Footer rules: Cancel uses `.keyboardShortcut(.cancelAction)`; primary action uses `.keyboardShortcut(.defaultAction)` and `.buttonStyle(.glassProminent)`.

### Tab Hit Targets

Custom tab bars must expand tappable area with `.contentShape(.rect)` on the label content. See `SpecImportSourceTabBar.swift`:

```swift
Label(tab.label, systemImage: tab.systemImage)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 6)
    .contentShape(.rect)  // required for full-width tap target
```

Pair with `.buttonStyle(.plain)` and accent-backed selection background. Add `accessibilityIdentifier` per tab for UI tests.

## Layout and Navigation

### NavigationSplitView (macOS / iPad)

`ProjectManagerView` is the root shell. It uses a **2-column** `NavigationSplitView` with a **3-level logical hierarchy** (projects → requests → editor):

| Column | Content |
|--------|---------|
| Sidebar | `ProjectSidebarView` when no project selected; `RequestListView` when project selected |
| Detail | `WelcomeView` / `ProjectWelcomeView` / `RequestEditorView` via `ProjectManagerDetailView` |

Sidebar width: `.navigationSplitViewColumnWidth(min: 200, ideal: 290, max: 400)`.

**Never add "No X Selected" placeholder panes.** Views render their full layout immediately. Use contextual empty states (`ContentUnavailableView`, `SidebarEmptyState`) inside the active column, not blank selection placeholders.

### Auto-Selection

- After creating a project: set `selectedProjectId` in `ProjectEditSheet` create callback.
- After adding a request: `ProjectManagerView.addRequest` sets `selectedRequestId`.
- After spec import: `ProjectManagerSheets.selectProjectAfterSpecImport` selects project and first HTTP request.
- Empty project on appear: `RequestListView` opens `ProtocolPickerSheet` automatically.

### iPhone (`isPhone`)

`isPhone` from `Design/PlatformHelpers.swift` gates phone-only layout:

- `NavigationStack` with `navigationDestination` for project → request list → editor push.
- Sidebar back button in request list: `Label("Projects", systemImage: "chevron.backward")`.
- `ProjectManagerDetailView` returns `Color.clear` for project-without-request (editor is pushed on phone).

### HTTP Request Layout

`HttpRequestFullView` uses a custom resizable split (not `VSplitView`): `HttpRequestTabs` above, `ResizableDivider`, `HttpResponsePanel` below. Split ratio persisted per request in `UIStateStore`.

## Platform Conditionals

Single universal target. Use `#if os(macOS)` / `#else` for platform-specific code.

| Concern | Pattern |
|---------|---------|
| Sheet sizing | Wrap `.frame(width:height:)` in `#if os(macOS)` only; iOS sizes sheets naturally |
| Menu commands | `@FocusedValue` / `.focusedSceneValue` in `#if os(macOS)` (`ProjectFocusedValues`, `HttpFocusedValuesModifier`, `RequestEditorView`) |
| Text fields | macOS: `.textFieldStyle(.roundedBorder)`; iOS: default style |
| Settings | macOS: `Settings {}` scene in `ReqeastApp`; iOS: sheet via `ProjectManagerSettingsContent` |
| Hover | `onContinuousHover`, `onExitCommand` — macOS only |

### Cross-Platform Helpers (Services/)

- **Images**: `PlatformImage` type alias + `Image(platformImage:)` — never `NSImage`/`UIImage` directly in views (`ProjectIconView`, `HttpResponseImageView`).
- **Clipboard**: `PlatformClipboard.copy()` — never `NSPasteboard`/`UIPasteboard` in views (`RequestEditorView` copy URL action).

### Compact vs Regular Width

Use `@Environment(\.horizontalSizeClass)` to adapt toolbars and tab pickers:

- Compact: overflow `Menu` ("More"), sheet-based history, horizontal scrolling glass tab buttons (`HttpRequestTabs`).
- Regular: full toolbar buttons, segmented `Picker` for tabs.

## SourceEditorView (Read-Only Workaround)

macOS uses `CodeEditSourceEditor`. Known bug: `isEditable: false` breaks cursor placement and double-click word selection.

**Workaround** (always use for response/read-only editors):

1. Pass `isEditable: true` in `SourceEditorConfiguration.behavior`.
2. When `isResponse`, attach `ReadOnlyCoordinator` via `coordinators:`.
3. `ReadOnlyCoordinator` implements `TextViewDelegate.shouldReplaceContentsIn` returning `false` to block edits while preserving selection/copy.

iOS path in the same file: native `TextEditor` (editable JSON) or `UITextView` representable (read-only highlighted responses) with `.textSelection(.enabled)`.

## Error Display

Reqeast is a developer tool. Error UX is critical.

### RequestError

- Store errors as `RequestError`, never `String?`.
- Display `error.localizedTitle` + `error.iconName` (per-kind SF Symbol from `Models/RequestError.swift`).
- Always `.textSelection(.enabled)` on error message `Text`.

Canonical pattern (`HttpResponsePanel`):

```swift
ContentUnavailableView {
    Label(error.localizedTitle, systemImage: error.iconName)
} description: {
    Text(error.message)
        .textSelection(.enabled)
}
```

### Spec Errors

`SpecImportError` follows the same icon/title pattern. `SpecImportErrorView` and `SpecSyncInlineErrorView` show full detail in monospaced, scrollable, selectable text.

### Conversation Logs (TCP/UDP/WebSocket/SSE/gRPC)

- Errors in system messages: `.foregroundStyle(.red.opacity(0.8))`, not `.secondary` (`TcpMessageRow`).
- All message text: `.textSelection(.enabled)`.
- Reuse `Shared/ConversationLog.swift` with `TcpMessageRow` (also used by WebSocket/SSE event rows and gRPC streaming messages).
- Unary gRPC responses use `GrpcResponseLog` (JSON/Hex toggle, status bar). Gate decorative loading pulse on `accessibilityReduceMotion`.

### Cloud Sync Errors

`CloudSync/CloudSyncErrorHeader` + `CloudSyncErrorContent` use `RequestError` with selectable detail text.

## Localization

String catalog: `Reqeast/Localizable.xcstrings`. **All 9 languages required** for every new user-facing string: en, zh-Hans, zh-Hant, ja, fr, pt-BR, es, ko, de.

| Auto-localized (use string literals) | Manual localization required |
|--------------------------------------|------------------------------|
| `Text()`, `Button()`, `Label()`, `Toggle()`, `Picker()`, `Section()`, `.navigationTitle()`, `.help()`, `TextField` placeholders | Computed `String` properties, helper `String` params rendered in `Text()`, enum `.rawValue` as display text |

Rules:

- Enums shown in UI: add `localizedName` with `String(localized:)`; use `.localizedName` in views, not `.rawValue` (`HttpRequestTab.localizedName`).
- Helper functions accepting `String` labels (`HttpResponseInfoRow`, popover section helpers): pass `String(localized:)` at call site.
- Protocol terms stay untranslated: HTTP methods, header names, TCP/UDP/WS/SSE, encoding names.
- Log/diagnostic strings stay English.
- Pluralization: configure variants in String Catalog, not manual ternaries.

## Text Input

**Every** `TextField`, `TextEditor`, and `SecureField` must include `.devTextInput()` from `Design/InputModifiers.swift` (disables autocorrect; iOS also disables autocapitalization).

For single-line fields that must reject newlines, use `Binding.strippingNewlines()`.

macOS `TextField` in forms typically also uses `.textFieldStyle(.roundedBorder)`.

## File Size Limits

Spec import enforces `SpecImportHelpers.maxBytes` (= `SafeFetchLimits.maxBodyBytes`, 5 MiB):

- URL fetch: HTTPS only; caption in `SpecImportURLSourceView`.
- Paste tab: live byte count via `SpecImportHelpers.byteCountLabel`; red when over limit; continue disabled in `SpecImportSheet+SourceActions`.
- File/folder import: validated in `SpecImportSheet+ImportActions`.

Show limits in UI copy; gate actions with `canContinueFromSource` / `canCommitImport` guards.

## File Size and Structure

Keep Swift view files under **~150 lines**. Split by extracting:

- Subviews into dedicated files (`SpecImportSourceViews`, `HttpResponseBodyContent`).
- `ViewModifier` types (`ProjectManagerSheets`, `HttpRequestBehaviorModifier`).
- `extension ViewName` for sheet chrome (`SpecImportSheetChrome`, `SpecImportSheetLayout`).
- Accessibility enums per feature area (`SpecImportAccessibility`, `SpecSyncAccessibility`, `SpecExportAccessibility`).

Naming: one primary `struct` per file matching the filename. Group related small views in a folder (e.g. `Http/Auth/`).

## Subfolder Map

```
Views/
  ProjectManagerView.swift      # Root NavigationSplitView shell
  ProjectManagerDetail.swift    # Detail column routing
  ProjectManagerSheets.swift    # Centralized sheet modifier
  ProjectFocusedValues.swift    # macOS menu command bindings
  RequestEditorView.swift       # Protocol switch → *RequestFullView
  RequestListView.swift         # Request sidebar + spec sync toolbar

  Http/                         # HTTP request/response editors (largest subtree)
    Auth/                       # Per-auth-type credential editors
    SourceEditorView.swift      # Code editor (macOS CodeEdit / iOS native)
    ReadOnlyCoordinator.swift   # macOS read-only editor guard
    HttpRequestView.swift       # HTTP layout orchestration
    HttpResponse*.swift         # Response tabs, body, headers, info sections
    JqFilter*.swift             # jq filter bar and help views

  Tcp/                          # TcpRequestFullView, connection bar, message rows
  Udp/                          # UdpRequestFullView
  WebSocket/                    # WebSocketRequestFullView, connection bar
  Sse/                          # SseRequestFullView, event rows
  Grpc/                         # GrpcRequestFullView, connection bar, schema/proto library, response log
  Shared/                       # ConversationLog (reused by socket protocols + gRPC streams)
  Environment/                  # Environment manager, editor, toolbar picker

  SpecImport/                   # OpenAPI/Postman/HAR import flow
  SpecSync/                     # Linked spec sync, review, read-only banner
  SpecExport/                   # Spec export and review sheets
  Export/                       # Project/bundle import-export (non-spec)
  CloudSync/                    # iCloud sync error UI

  (root)                        # Project/request chrome, settings, sheets, welcome
```

### Protocol View Pattern

Each protocol follows the same shape:

1. `*RequestFullView` — top connection/URL bar, optional `SpecReadOnlyBanner` / `GrpcReadOnlyBanner`, scrollable content.
2. Connection bar — host/port/URL/authority fields with `.devTextInput()`, glass connect/send buttons.
3. Message/event log — `ConversationLog` or protocol-specific rows (`GrpcResponseLog` for unary gRPC).
4. `MessageHistoryButton` / `MessageSettingsButton` for TCP/UDP/WS/SSE toolbars.

gRPC specifics (`Views/Grpc/`):

- `GrpcConnectionBar` — authority + TLS toggles; unary/server-streaming Send; client/bidi Connect/stop; server streaming also shows stop while the stream is active.
- `GrpcSchemaPanel` — proto bundle vs server reflection; Manage Proto Library / Import… open `GrpcProtoLibrarySheet` (Import… sets `shouldStartImport` so the sheet starts the file picker).
- `GrpcMethodPicker` — service/method pickers or manual fields when no descriptors.
- `GrpcBodyEditor` — JSON/Hex body; stream Send / Half-close / Cancel for non-unary kinds.
- Info bars use glass (orange-tint discovery banner; neutral glass `GrpcReadOnlyBanner` when proto assets are missing).

`RequestEditorView` switches on `request.type` and adds shared toolbar items (`EnvironmentToolbarPicker`, HTTP-only import/snippet/history).

## SpecImport UI Conventions

Entry: `SpecImportSheet` presented from `ProjectManagerSheets` / sidebar.

**Phases**: `sourcePick` → `parsing` → `preview` → `importing` → `error`.

**Source tabs** (`SpecImportSourceTabBar`): File / URL / Paste. File tab uses inline glass buttons; URL/Paste use footer "Continue"/"Fetch" prominent button.

**Key files**:

| File | Role |
|------|------|
| `SpecImportSheetLayout.swift` | macOS/iOS body chrome |
| `SpecImportSheetChrome.swift` | Phase content + footer/toolbar buttons |
| `SpecImportSheet+SourceActions.swift` | URL fetch, paste parse triggers |
| `SpecImportSheet+ImportActions.swift` | Commit import, post-import navigation |
| `SpecImportPreviewView.swift` | Target project, options, counts |
| `SpecImportTargetSection.swift` | New vs existing project picker |
| `SpecImportAdvancedOptionsView.swift` | Schema synthesis, HAR credentials, etc. |
| `SpecImportErrorView.swift` | Full error detail, Try Again |
| `SpecImportAccessibility.swift` | UI test identifiers |

**Import target**: new project or merge into existing. Link-to-spec option stores URL snapshot for `SpecSync`.

**DEBUG**: `SpecImportPresentationState` + `applyUITestFixturesIfNeeded()` for UI tests.

## SpecSync UI Conventions

For projects with `specLink`:

- `SpecStatusToolbarBadge` in `RequestListView` toolbar opens `SpecLinkPanelView`. Icon only; no visible label text.
- `SpecSyncReviewSheet` shows diff segments (added/changed/removed) with selectable rows.
- `SpecReadOnlyBanner` in HTTP/TCP/etc. views when spec bytes unavailable on device.
- `SpecSyncInlineErrorView` for apply/fetch failures.
- Stale request filtering and bulk delete via `RequestListView` stale menu.
- `SpecSyncAccessibility` identifiers on review controls.

Read-only spec projects: disable editors via `isReadOnly` / `.disabled(isSpecReadOnly)` passed to tabs and fields.

## SpecExport UI Conventions

Entry: `ExportSpecSheet` via `specExportTarget` binding from project context menu.

- Kind picker (OpenAPI/Postman) with `.tint(.primary)`.
- `SpecExportReviewSheet` for conflict/selection review before `fileExporter`.
- `SpecExportReviewRows` with selectable diff detail.
- `SpecExportPresentationState` for DEBUG UI-test presentation (mirrors SpecImport).
- Errors shown with `.textSelection(.enabled)`.

## Related Design Files

Views depend on `Reqeast/Design/`:

| File | Use in Views |
|------|-------------|
| `InputModifiers.swift` | `.devTextInput()` |
| `PlatformHelpers.swift` | `isPhone` |
| `BrandTheme.swift` | Brand tint (logo/paywall only), spring animations |
| `ReqeastEditorTheme.swift` | macOS `SourceEditorView` themes |
| `AnimationModifiers.swift` | Staggered entrance animations |
| `RequestDataBindable.swift` | Shared request field binding (`HttpRequestTabs`) |

## Dependencies

Views call but do not implement:

- `Services/HttpService`, `TcpService`, `UdpService`, `JqFilterService`
- `Services/PlatformImage`, `PlatformClipboard`
- `Services/*Import*`, `*Export*`, `CloudSyncService`
- `Models/ProjectStore`, `RequestError`, session stores

Keep networking and parsing out of views. Views orchestrate state, presentation, and user input only.

## Testing Hooks

- `accessibilityIdentifier` on spec import/sync/export controls (stable string constants in `*Accessibility.swift` enums).
- `#if DEBUG` presentation states for UI tests (`SpecImportPresentationState`, `SpecExportPresentationState`, `SpecSyncUITestSupport`).
- `StorageEnvironment.isScreenshotMode` / `isRunningTests` adjusts sheet heights in `SpecImportSheetLayout`.

## Context7

Query Context7 before using unfamiliar SwiftUI APIs (navigation, glass styles, sheet modifiers, `scrollEdgeEffectStyle`, `fileImporter`/`fileExporter`).