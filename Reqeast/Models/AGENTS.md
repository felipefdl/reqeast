# Models Layer

Agent guide for `Reqeast/Models/`. Read [`../../AGENTS.md`](../../AGENTS.md) for app-wide architecture and iCloud sync overview. This file covers persistence, `@Observable` stores, and `CloudSyncable` data shapes only.

## What This Layer Owns

- **Domain models**: `Project`, `Request`, `ApiEnvironment`, protocol request payloads (`HttpRequestData`, etc.), spec-import types (`SpecDocument`, `SpecLink`, `SpecOperationSnapshot`).
- **Persistence**: UserDefaults-backed JSON arrays keyed via `StorageEnvironment.keyPrefix`. Spec file bytes live on disk under Application Support (`specs/`), not in UserDefaults.
- **Central store**: `ProjectStore` (`@MainActor`, `@Observable`) holds in-memory arrays and coordinates local save + CloudKit queue calls.
- **Session/UI state**: `HttpSessionStore`, `TcpSessionStore`, `UIStateStore`, etc. are ephemeral or file-backed; they do not implement `CloudSyncable`.
- **Sync contract**: Models conform to `CloudSyncable` (defined in `Services/CloudSyncable.swift`). `CloudSyncService` serializes them; `ProjectStore+RemoteSync` applies inbound records.

Models do **not** own networking (Rust/UniFFI), view layout, or CKSyncEngine delegate logic.

## ProjectStore File Split

`ProjectStore.swift` holds the class shell: properties, `init`, `mock()`, lifecycle observers, `resetAllData()`, spec read-only helper. All behavior lives in extensions:

| File | Responsibility |
|------|----------------|
| `ProjectStore+Persistence.swift` | `load`, `saveLocal`, `saveLocalOrThrow`, `encodeAll`, deduplication |
| `ProjectStore+RemoteSync.swift` | `withRemoteBatch`, `applyRemoteUpsert`, soft-delete, cascade delete, purge |
| `ProjectStore+Projects.swift` | Project CRUD, duplicate |
| `ProjectStore+Folders.swift` | Project-folder CRUD |
| `ProjectStore+Requests.swift` | Request + request-folder CRUD |
| `ProjectStore+Environments.swift` | Environment CRUD |
| `ProjectStore+BulkImport.swift` | `performBulkImport`, `performBulkMerge`, payload validation |
| `ProjectStore+StaleOperations.swift` | Spec stale dismiss, bulk delete stale requests |

**Convention**: one extension per concern; name `ProjectStore+<Topic>.swift`. New bulk or sync paths get their own file rather than growing `ProjectStore.swift`. Keep files under ~150 lines.

## CloudSyncable Protocol

```swift
protocol CloudSyncable: Codable, Identifiable where ID == UUID {
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    static var syncRecordType: SyncRecordType { get }
}
```

Conforming types: `Project`, `ProjectFolder`, `Request`, `RequestFolder`, `ApiEnvironment`, `SpecDocument`. Each record is a full JSON blob in CKRecord `data`; LWW uses `updatedAt`.

- Call `touch()` immediately before `queueSave` / batch inclusion so local edits win conflicts.
- Call `tombstone()` for soft-delete; sets both `updatedAt` and `deletedAt` to now.
- Remote upsert rule: `remote.updatedAt >= local.updatedAt` (server wins ties). Soft-deleted locals and tombstoned IDs block upserts.
- `schemaVersion` on models uses `CloudSyncableSchema.decodeVersion`; reject blobs above `currentVersion` to avoid truncating unknown fields on re-upload.

When adding a syncable type: extend `SyncRecordType`, add `CloudSyncable` conformance, update `applyRemoteUpsert`, `purgeDeletedItem`, `applyRemoteDeletion`, `touchLocalItem`, `encodeAll`/`load`, and `CloudSyncService` record switches.

## Scale Rules (Critical)

Users may have hundreds of requests and full OpenAPI specs. Sync work must be **proportional to changed items**.

- **Never** call `queueSaveAll()` from CRUD or refresh paths. `saveAll()` is `saveLocal()` only.
- Single-item edits: `saveAll()` + `CloudSyncService.queueSave(item)`.
- Multi-item atomic writes: `queueSaveBatch(project:folders:requests:environments:specDocument:)` once. Children queue before `Project`.
- Bulk import / spec apply: one `saveLocalOrThrow()` commit, then one `queueSaveBatch` with only affected records.
- `queueSaveAll()` remains for migration and explicit full-sync only.

## Three Flags: Never Conflate

| Flag | Set by | Purpose |
|------|--------|---------|
| `isLoading` | `load()`, `withRemoteBatch`, cascade deletes, duplicates | Suppresses array `didSet` side effects (MCP export) and `saveAll` guards |
| `importInProgress` | `performBulkImport` / `performBulkMerge` | Blocks remote upserts/deletes/purges during atomic import |
| `syncApplyInProgress` | `SpecSyncService.apply` | Blocks remote upserts during Rule A spec sync apply |

`withRemoteBatch` sets `isLoading` only; it does **not** clear `importInProgress` or `syncApplyInProgress`. `applyRemoteUpsert`, `purgeDeletedItem`, and `applyRemoteDeletion` no-op when either import or sync-apply lock is active. Array `didSet` guards check all three locks plus `mockMode`.

## Soft-Delete and Tombstones

Soft-delete: set `deletedAt` + bump `updatedAt` via `tombstone()`. `softDeleteAll()` tombstones every item and returns IDs for tracking.

`DeletionTombstoneStore` (UserDefaults `[UUID: Date]`) records IDs deleted locally so late-arriving CloudKit records cannot resurrect ghosts. `cascadeDeleteProject` and `deleteRequests` call `tombstones.add(ids:)`. `applyRemoteUpsert` returns early if `tombstones.contains(item.id)` or parent project is tombstoned.

Hard removal from arrays happens in `purgeDeletedItem` (after CK confirms deletion) or `applyRemoteDeletion` (remote hard delete). User reset uses `softDeleteAll()`; zone wipe uses `resetAllData()`.

## Spec Import Models

**`SpecLink`** (on `Project`): format, source (`SpecSource`), fingerprint, `specRevision`, sync timestamps, `isDetached`, `backgroundCheckEnabled`. Linked live sources may schedule background fingerprint checks.

**`SpecDocument`** (`CloudSyncable`, one per linked project, `id == projectId`): metadata + optional CKAsset for spec bytes. `classification` (`.standard` vs `.internal`) controls asset upload and `sourceURL` redaction in `syncedRepresentation()`. `assetHydrated` drives read-only mode via `ProjectStore.isSpecProjectReadOnly`.

**`SpecOperationIdentity`**: stable `primaryKey` + `alternateKeys` for matching operations across spec revisions. `Request.id` never changes.

**`SpecOperationSnapshot`**: canonical baseline of spec-owned HTTP fields (method, URL, params, headers, body). Stored as gzip JSON in `Request.specSnapshotPayload`; fingerprint in `Request.specFieldFingerprint`.

**`Request` spec fields**: `specIdentity`, `specLastSyncedAt`, `isSpecStale`, `specFieldFingerprint`, `specSnapshotPayload`. Stale ops are user-dismissed only (`dismissSpecStale`); sync never auto-clears.

### Bulk Import Pipeline (`ProjectStore+BulkImport`)

Four stages: (1) stage + `touch()` typed arrays, (2) validate CK payload sizes before mutation, (3) commit arrays + `saveLocalOrThrow()` with snapshot rollback on failure, (4) single `queueSaveBatch`. `performBulkMerge` is append-only into an existing project.

### Spec Sync Apply (`SpecSyncService`, not in Models but drives store locks)

`syncApplyInProgress = true` for full apply. Rule A merge: spec wins method; URL/body unless locally modified vs baseline; params/headers merge preserves user-disabled and user-added rows; auth stays user-owned. On failure, in-memory snapshot restores before rethrow. Success: `saveLocalOrThrow()`, then `queueSaveBatch` with affected requests + `SpecDocument`, project last. Do not overwrite spec-owned fields when local `specFieldFingerprint` differs from incoming unless user confirmed sync on this device.

## Persistence Patterns

- Keys: `ProjectStore.<collection>Key` using `StorageEnvironment.keyPrefix` (`test.`, `screenshot.`, `debug.`, or `""` in Release).
- `load()` sets `isLoading`, decodes arrays, `deduplicate()` by ID keeping newest `updatedAt`, then clears `isLoading`.
- Corrupt UserDefaults data: log fault, backup to `*_corrupt_backup`, return empty/nil.
- `saveLocalOrThrow()`: encode all six arrays atomically; throws on failure (bulk import/sync apply depend on this for rollback).
- `saveLocal()`: wraps `saveLocalOrThrow()` and logs fault on error (normal CRUD path).
- Background entry calls `saveLocal()`; does not queue full CloudKit sync.

## StorageEnvironment

Detects `isRunningTests` (XCTest env var) and `isScreenshotMode` (launch args). Derives isolated prefixes for UserDefaults keys and directory names (`sessions`, `specs`, `mcp`). `ProjectStore` skips `CloudSyncService.start()` in test/screenshot modes. Use `ProjectStore.mock()` for unit tests (`mockMode` suppresses persistence and MCP export).

## Implementation Rules for Agents

1. **Touch before sync**: any mutation queued to CloudKit must call `touch()` on the copy being saved.
2. **Rollback on atomic writes**: bulk import and spec apply snapshot arrays before commit; restore on `saveLocalOrThrow()` failure.
3. **Typed staging**: touch and validate concrete `[Request]` etc., not `[any CloudSyncable]` (existential `touch()` pitfall).
4. **Validate before mutate**: `validateCloudKitPayload` runs pre-commit in bulk import; reject oversize records with `BulkImportError.recordTooLarge`.
5. **Proportional CloudKit**: batch only changed items; never re-queue entire store on a single edit.
6. **Spec bytes on disk**: `SpecDocument.hasLocalSpecBytes` / `localSpecFileURL`; CKAsset is hydration fallback, not primary local store.
7. **New model fields**: add `decodeIfPresent` defaults in custom `init(from:)` for backward compatibility; bump `CloudSyncableSchema.currentVersion` only on breaking changes.

## Related Code Outside Models

- `Services/CloudSyncService.swift`: `queueSave`, `queueSaveBatch`, engine lifecycle
- `Services/SpecSyncService.swift`, `Services/SpecImportService.swift`: import/apply orchestration
- `ReqeastTests/Models/`: `ProjectStoreSyncTests`, `ProjectStoreBulkImportTests`, `ProjectStoreStaleOperationsTests`