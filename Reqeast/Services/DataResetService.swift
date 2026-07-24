//
//  DataResetService.swift
//  Reqeast
//

import Foundation
import os

private let logger = Logger(subsystem: "app.reqeast", category: "DataResetService")

enum DataResetCategory: Equatable {
    case keychain
    case sessionFiles

    var localizedLabel: String {
        switch self {
        case .keychain: String(localized: "Keychain credentials")
        case .sessionFiles: String(localized: "Session files")
        }
    }
}

struct DataResetFailure: Identifiable {
    let id = UUID()
    let category: DataResetCategory
    let underlying: Error
}

struct DataResetError: Error {
    let failures: [DataResetFailure]
}

@MainActor
enum DataResetService {
    /// Resets all local + iCloud data. Throws `DataResetError` containing every partial failure
    /// so the UI can surface them individually. The soft-delete and CK-delete steps always run,
    /// even if keychain or session-file deletion fails, so the sync side converges.
    static func resetAllData(store: ProjectStore) throws {
        var failures: [DataResetFailure] = []

        SessionRegistry.shared.removeAllSessions()

        do {
            try KeychainService.shared.deleteAllCredentials()
        } catch {
            logger.fault("Failed to delete Keychain credentials during reset: \(error)")
            failures.append(DataResetFailure(category: .keychain, underlying: error))
        }

        do {
            try GitTokenKeychainService.shared.deleteAllTokens()
            GitOAuthAccountRegistry.clear()
        } catch {
            logger.fault("Failed to delete Git PAT tokens during reset: \(error)")
            failures.append(DataResetFailure(category: .keychain, underlying: error))
        }

        do {
            try SessionPersistenceService.shared.deleteAllSessions()
        } catch {
            logger.fault("Failed to delete session files during reset: \(error)")
            failures.append(DataResetFailure(category: .sessionFiles, underlying: error))
        }

        let defaults = UserDefaults.standard
        for key in [
            "defaultTimeout", "followRedirects", "jsonIndentSpaces", "maxHistoryEntries",
            "strictHttpMode", "mcpExportEnabled", "lastMCPSetupClient", "lastCodeSnippetTarget",
            "jqUnquoteStrings", SafeFetchTrustedHosts.storageKey,
        ] {
            defaults.removeObject(forKey: key)
        }

        let deletedIds = store.softDeleteAll()
        DeletionTombstoneStore.shared.add(ids: deletedIds)

        CloudSyncService.shared.queueDeleteAll()
        // A fresh start should not display an error from the world that was just erased.
        // Per-record caches (dirty, oversized, system fields) clear as the deletes confirm.
        CloudSyncService.shared.syncState.reset()

        if !failures.isEmpty {
            throw DataResetError(failures: failures)
        }
    }
}
