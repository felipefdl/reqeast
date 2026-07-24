//
//  SpecSyncUITestSupport.swift
//  Reqeast
//

import Foundation

#if DEBUG
/// Deterministic spec fetch fixtures for `SpecSyncUITests` (no network).
enum SpecSyncUITestSupport {
    static let testHost = "spec-sync-ui.example.test"
    static let testURL = "https://\(testHost)/petstore.yaml"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-specSyncUITest")
    }

    static var renameOperationId: String? {
        launchArgumentValue(for: "-specSyncUITestRenameOp=")
    }

    static var renameRequestName: String? {
        launchArgumentValue(for: "-specSyncUITestRenameTo=")
    }

    @MainActor
    static func applyRenameIfNeeded(store: ProjectStore, projectId: UUID) {
        guard isEnabled,
              let operationId = renameOperationId,
              let newName = renameRequestName,
              let request = store.requests(for: projectId).first(where: {
                  $0.specIdentity?.primaryKey == operationId
              }) else {
            return
        }
        store.renameRequest(request, to: newName)
    }

    private static func launchArgumentValue(for prefix: String) -> String? {
        guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let value = String(raw.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var fetchCounts: [String: Int] = [:]

    static func fetchData(for url: URL) -> Data? {
        guard (isEnabled || StorageEnvironment.isRunningTests), url.host == testHost else { return nil }

        let key = url.absoluteString
        let index = lock.withLock {
            let current = fetchCounts[key, default: 0]
            fetchCounts[key] = current + 1
            return current
        }

        let yaml = index == 0 ? fixtureV1 : fixtureV2
        return Data(yaml.utf8)
    }

    /// v1: two operations. v2: `listPets` summary changed; `getPetById` removed.
    private static let fixtureV1 = """
    openapi: 3.1.0
    info:
      title: Spec Sync UI Test
      version: 1.0.0
    servers:
      - url: https://spec-sync-ui.example.test/v1
    paths:
      /pet:
        get:
          summary: List all pets
          operationId: listPets
          responses:
            "200":
              description: Successful operation
      /pet/{petId}:
        get:
          summary: Find pet by ID
          operationId: getPetById
          parameters:
            - name: petId
              in: path
              required: true
              schema:
                type: integer
          responses:
            "200":
              description: Successful operation
    """

    private static let fixtureV2 = """
    openapi: 3.1.0
    info:
      title: Spec Sync UI Test
      version: 2.0.0
    servers:
      - url: https://spec-sync-ui.example.test/v1
    paths:
      /pet:
        get:
          summary: List pets from spec
          operationId: listPets
          responses:
            "200":
              description: Successful operation
    """
}
#endif