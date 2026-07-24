# ReqeastTests

Swift unit tests for Reqeast. Uses **Swift Testing** (`import Testing`), not XCTest. No real network calls.

## Running Tests

```sh
TZ=UTC just test-swift       # macOS
TZ=UTC just test-swift-ios   # iOS Simulator (iPhone 17)
just test-all                # Rust + Swift macOS (default CI gate)
```

Always set `TZ=UTC` so timestamp-sensitive assertions (AWS SigV4, Akamai EdgeGrid, JWT) are deterministic.

Opt-in suites excluded from `just test-all`:

```sh
just test-spec-perf              # RUN_SPEC_PERF — SpecImportPerformanceTests
just update-spec-perf-baseline   # Refresh stress-500 baseline JSON
just test-ckasset-harness        # RUN_CKASSET_HARNESS — CKAssetValidationHarnessTests
just record-ckasset-harness      # Record CKAsset timing fixtures
```

## File Layout

Mirror `Reqeast/` source structure:

| Directory | Mirrors |
|-----------|---------|
| `Models/` | `Reqeast/Models/` |
| `Services/` | `Reqeast/Services/` |
| `Views/` | View helpers and small UI logic |
| `Fixtures/` | Golden files, not test code |

Name files `<Type>Tests.swift`. One `@Suite` per logical area; multiple suites per file is fine for distinct sub-areas.

## Swift Testing Conventions

```swift
import Testing
@testable import Reqeast

@Suite("ProjectStore", .serialized)
struct ProjectStoreTests {
    @Test @MainActor func addAndRetrieveProject() {
        let store = ProjectStore.mock()
        #expect(store.projects.count == 1)
    }
}
```

- **`@Test`**: one behavior per function. Use `@Test(arguments:)` for parameterized goldens.
- **`#expect` / `#require`**: assertions.
- **`@Suite("Name")`**: groups tests in Xcode navigator.
- **`@Suite(..., .serialized)`**: required for shared global state (UserDefaults, `CloudSyncService.shared`, file overrides, mock URL handlers). Used by most `ProjectStore*`, `SpecImport*`, `SpecSync*`, `CloudSync*`, `Git*` suites.
- **`@MainActor`**: annotate tests touching `@MainActor` types.
- **`.enabled(if:)`**: gate opt-in suites (`SpecImportPerformance`, `CKAssetValidationHarness`).
- **Structs, not classes**: test types are `struct`.

Do not add XCTest to this target.

## Storage Isolation

`StorageEnvironment` separates persistence:

| Context | UserDefaults prefix | Specs / sessions dirs |
|---------|--------------------|-----------------------|
| Tests (`XCTestConfigurationFilePath` set) | `test.` | `specs-test`, `sessions-test` |
| Screenshot (`-screenshotMode`) | `screenshot.` | `specs-screenshot`, `sessions-screenshot` |
| Debug app | `debug.` | `specs-debug`, `sessions-debug` |
| Release | (none) | `specs`, `sessions` |

UITests pass `-screenshotMode` but run under XCTest, so `test.` wins (prevents parallel UI runs from clobbering screenshot UserDefaults).

**`ProjectStore.mock()`** creates in-memory store (`mockMode: true`), skips `setupStorage()`, `load()`, and CloudSync. Use for almost all store tests:

```swift
let store = ProjectStore.mock(projects: [project], requests: [request])
```

For file I/O, override service roots and clean up in `defer`:

```swift
SpecImportService.specsRootDirectoryOverride = tempRoot
defer { SpecImportService.specsRootDirectoryOverride = nil; try? FileManager.default.removeItem(at: tempRoot) }
```

## No Real Network

- **In-memory fixtures** (`ReqeastTests/Fixtures/`)
- **`MockURLProtocol`** + injectable resolver (`SafeFetchServiceTests`)
- **`SpecSyncUITestSupport.fetchData(for:)`** for `spec-sync-ui.example.test`
- **Rust `parse_spec`** on local bytes only

Auth tests inject fixed timestamps/nonces for deterministic signatures.

## Spec Import Golden Fixtures

Two-layer pipeline:

1. **Rust normalization** (`rust/tests/spec_import_golden.rs`): `*.input.*` → `*.normalized.json`. Regenerate: `just update-spec-goldens`
2. **Swift mapper parity** (`SpecImportMapperTests`): `*.normalized.json` → `*.project.json`. Regenerate: `just update-spec-project-goldens`

Fixture path resolves `SRCROOT` when set, else walks from `#filePath` to `ReqeastTests/Fixtures/SpecImport/`.

Key families: OpenAPI (`petstore-*`), Postman/Insomnia/Bruno, HAR, AsyncAPI, GraphQL, `stress-500` (perf), `duplicate-operation-id` (errors).

Related suites: `SpecImportServiceTests`, `SpecImportMapperTests`, `SpecSyncServiceTests`, `SpecExportServiceTests`, `SpecExportRoundTripTests`, `SpecSnapshotServiceTests`.

## Opt-In Suites

**`SpecImportPerformanceTests`**: stress-500 SLO (p95 ≤ 5s, main-thread hang ≤ 100ms). Requires `RUN_SPEC_PERF` and `-parallel-testing-enabled NO` (parallel suites inflate hang probes).

**`CKAssetValidationHarnessTests`**: 5 MiB `SpecDocument` CloudKit scenarios. Requires `RUN_CKASSET_HARNESS`. Non-gating spike.

## Adding New Tests

1. Place under matching `Models/`, `Services/`, or `Views/` subdirectory.
2. Use `ProjectStore.mock()` unless testing real persistence.
3. Add `.serialized` for shared singletons or global overrides.
4. Spec import changes: update input fixture, run both golden update commands, commit generated JSON.
5. Inject deterministic dates/seeds for crypto or time-based output.