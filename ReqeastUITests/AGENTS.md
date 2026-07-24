# ReqeastUITests

UI automation for Reqeast. Uses **XCTest only** (`XCUIApplication`, `XCTAssert*`). Swift Testing cannot drive UI elements.

## Running Tests

```sh
TZ=UTC just test-ui       # macOS — -parallel-testing-enabled NO (required)
TZ=UTC just test-ui-ios   # iOS Simulator (iPhone 17) — -parallel-testing-enabled NO (required)
TZ=UTC just test-ui-screenshots   # ScreenshotTests only (RUN_SCREENSHOT_TESTS)
```

`-parallel-testing-enabled NO` is enforced in `justfile` for macOS and iOS. Parallel runs caused flaky timeouts and shared-state races.

`ScreenshotTests` are **opt-in**. `just test-ui` skips them (`-skip-testing` + compile gate). Marketing capture uses `just screenshots-capture`, which passes `RUN_SCREENSHOT_TESTS`.

## Test Files

| File | Purpose |
|------|---------|
| `ReqeastUITests.swift` | Sidebar, project/request selection, HTTP editor smoke |
| `SpecImportUITests.swift` | Import Spec: paste flow, merge into existing project |
| `SpecSyncUITests.swift` | Linked URL import, sync review, stale badges, rename preservation |
| `SpecExportUITests.swift` | Export OpenAPI → re-import round-trip op count |
| `GrpcUITests.swift` | gRPC editor smoke: create request, schema/RPC sections, proto library sheet, body mode + Send |
| `ScreenshotTests.swift` | Marketing screenshots (`test01_`…`test04_`); not a regression gate |
| `UITestHelpers.swift` | Shared waits, row lookup, paste/replace, import sheet opener |

## Launch Arguments

Every test: `continueAfterFailure = false`.

| Argument | Effect |
|----------|--------|
| `-screenshotMode` | Loads demo data synchronously (`DemoDataService.load` in `ReqeastApp.init`) |
| `-screenshotEmpty` | Clears all data (iPhone empty sidebar screenshot) |
| `-specImportUITest` | Prefills paste editor with petstore YAML |
| `-specSyncUITest` | Prefills URL, defaults link-to-spec, enables mock fetch |
| `-specSyncUITestRenameOp=` / `-specSyncUITestRenameTo=` | Rename hook for sync name-preservation test |
| `-specExportUITest` | Bypasses save panel; copies export YAML to pasteboard |
| `-AppleLanguages` / `-AppleLocale` | Screenshot language override |

```swift
app.launchArguments = ["-screenshotMode"]                              // layout tests
app.launchArguments = ["-screenshotMode", "-specImportUITest"]         // import
app.launchArguments = ["-screenshotMode", "-specSyncUITest"]           // sync (no network)
app.launchArguments = ["-screenshotMode", "-specImportUITest", "-specExportUITest"]  // export
```

## Storage Isolation

`-screenshotMode` / `-screenshotEmpty` must use **`screenshot.`** storage (demo data only), never `debug.` real projects. In `StorageEnvironment`, **screenshot mode wins over** `isRunningTests` for key prefixes and Application Support dirs. CloudSync does not start in screenshot or unit-test mode.

## UITestHelpers

- **`waitForDemoData`**: waits for `project-Weather API`, polls `isHittable`, settles.
- **`projectRow` / `requestRow`**: `project-<name>` / `request-<name>` with `staticTexts` + `descendants` fallback.
- **`paste(into:scope:)`**: pasteboard input; `scope` must be the sheet window for Cmd+V.
- **`openImportSpecSheet`**: macOS menu bar / welcome button / iOS Add menu; returns sheet window.

Use `Thread.sleep` (0.3–0.5s) after navigation. Poll `waitForExistence` for async button enablement.

## Accessibility Identifiers

Query by identifier, not localized label text.

**Sidebar**: `project-<name>`, `request-<name>` (on name `Text` views)

**Spec Import**: `spec-import-cancel-button`, `spec-import-continue-button`, `spec-import-import-button`, `spec-import-source-tab-paste`, `spec-import-source-tab-url`, `spec-import-paste-editor`, `spec-import-url-field`, `spec-import-fetch-button`, `spec-import-operation-count`, `spec-import-import-target-existingProject`, `spec-import-existing-project-picker`, `spec-import-existing-project-<name>` (iOS UITest mode)

**Spec Sync** (private `SpecSyncAccessibilityID` enums mirror app): `sync-review-toolbar-badge` (accessibility **value**: `linked`, `linked, N stale`, or `snapshot`), `sync-review-spec-link-panel`, `sync-review-check-for-updates`, `sync-review-summary-counts`, `sync-review-apply-button`, `sync-review-cancel-button`

**Protocol picker**: `protocol-picker-http`, `protocol-picker-tcp`, `protocol-picker-udp`, `protocol-picker-webSocket`, `protocol-picker-sse`, `protocol-picker-grpc`

**gRPC editor**: `grpc-authority-field`, `grpc-send-button`, `grpc-manage-proto-library`, `grpc-import-proto`, `grpc-proto-library-done`, `grpc-proto-library-import`, `protoBundleRow-<uuid>`, `grpcReadOnlyBanner`

**Other**: `spec-export-export-button`, `http-request-url-field`, `Add`, `add-request-menu`, `Projects`

Add `.accessibilityIdentifier(...)` in app code before writing UI tests.

## Spec Feature Tests

**`SpecImportUITests`**: `-specImportUITest` prefilled paste avoids flaky `TextEditor` typing. Candidate-element arrays for segmented controls (macOS exposes segments by index).

**`SpecSyncUITests`**: `waitForAppReady` (not demo data wait). `SpecSyncUITestSupport` serves v1/v2 YAML for `spec-sync-ui.example.test` (no network). Relaunch with rename hook args for name-preservation test.

**`SpecExportUITests`**: `SpecExportUITestSupport` records export and auto-prefills re-import paste.

## ScreenshotTests

**Playbook (mandatory):** [`scripts/SCREENSHOTS.md`](../scripts/SCREENSHOTS.md). Root short form: `Agents.md` → **Marketing screenshots**.

**Never fight the image.** Recapture on the plate’s sim. Never stretch wrong-device raws. Never paint system chrome. Partial: `LANGS=` + `DEVICES=`. Gate: `just screenshots-validate`.

- **Enable:** UITest Debug defines `RUN_SCREENSHOT_TESTS`. `just test-ui` skips this class. Capture: `just screenshots-capture` / `just screenshots`.
- **Cases:** `test01_` … `test04_` (`03` = protocol menu, must include gRPC).
- **Lang/config:** `SCREENSHOT_LANG` + `SCREENSHOT_APPLE_LOCALE` + `SCREENSHOT_PLATFORM` + **`/tmp/reqeast-screenshot-config`** (`lang`, `appleLocale`, `platform=mac|iphone|ipad|ipad11`). Not shell `$TMPDIR`.
- **macOS:** `app.activate()`; **do not** mutate title bar / toolbar in screenshot mode (match real `open -a` / `references/mac-1.png`); AppKit fallback only if WindowGroup never appears; `screencapture -l` of the real WindowGroup window.
- **iPhone `01`:** empty welcome (`-screenshotEmpty`) intentional.
- **iPad 13":** landscape demos → `raw/ipad/` (~1.33). **iPad 11":** multi only → `raw/ipad11/` (~1.45). UITest forces landscape + CFU; capture then simctl `-screenshotMode` **8s** demo fill (`reboot=0`). SpringBoard date language: locale + sim shutdown/boot per cell.
- **System chrome:** clear CFU (`com.apple.generativeexperiences.corefollowup`) + status 9:41; `dismissSystemChromeTips()`. Never paint PNG.
- **Titles:** `scripts/screenshot-titles.json`.

## Platform Differences

- **macOS**: menu bar (`File` → `Import Spec...` / `Export as OpenAPI...`), `click()`, sheet is separate window — scope keyboard to it.
- **iOS**: `tap()`, `Projects` back button to reach sidebar `Add` menu; long-press project row for export context menu. Import target uses `Picker` wheels/menus, not macOS glass buttons.
- **Spec toolbar badge**: icon-only on all platforms; use `UITestHelpers.specBadgeAccessibilityState` / `assertLinkedSpecBadge` (reads localized `accessibilityValue`, not the visible icon).
- Try `buttons`, `menuButtons`, `popUpButtons`, `radioButtons`, `segmentedControls`, `pickers` in candidate arrays.

## Adding New UI Tests

1. Add accessibility identifiers in SwiftUI views first.
2. Extend `UITestHelpers` for reused interactions.
3. Use DEBUG launch-arg fixtures for deterministic spec content; never assert on real network.
4. Run `TZ=UTC just test-ui` and `TZ=UTC just test-ui-ios` before pushing spec UI changes.