//
//  ProjectStore.swift
//  Reqeast
//

import Foundation
import os
import SwiftUI

private let logger = Logger(subsystem: "app.reqeast", category: "ProjectStore")

@MainActor
@Observable
class ProjectStore {
    static let shared = ProjectStore()
    static let projectsKey = "\(StorageEnvironment.keyPrefix)projects"
    static let foldersKey = "\(StorageEnvironment.keyPrefix)folders"
    static let requestsKey = "\(StorageEnvironment.keyPrefix)requests"
    static let requestFoldersKey = "\(StorageEnvironment.keyPrefix)requestFolders"
    static let environmentsKey = "\(StorageEnvironment.keyPrefix)environments"
    static let specDocumentsKey = "\(StorageEnvironment.keyPrefix)specDocuments"
    static let protoBundlesKey = "\(StorageEnvironment.keyPrefix)protoBundles"

    let storage = UserDefaults.standard
    var isLoading = false
    /// True while `performBulkImport` is mutating store arrays. Separate from `isLoading` —
    /// remote sync must not apply upserts/deletes until this clears.
    var importInProgress = false
    /// True while `SpecSyncService.apply` is mutating store arrays (P2).
    var syncApplyInProgress = false
    private let mockMode: Bool

    #if DEBUG
    /// Incremented by `saveLocalOrThrow()` while `importInProgress` during unit tests (AC17).
    var bulkImportSaveLocalCallCount = 0
    /// When true during `performBulkImport`, `saveLocalOrThrow()` throws `BulkImportError.localPersistFailed`.
    var bulkImportSaveLocalShouldFail = false
    /// Incremented by `saveLocalOrThrow()` while `syncApplyInProgress` during unit tests.
    var syncApplySaveLocalCallCount = 0
    /// When true during `SpecSyncService.apply`, `saveLocalOrThrow()` throws `BulkImportError.localPersistFailed`.
    var syncApplySaveLocalShouldFail = false
    #endif

    var projects: [Project] = [] {
        didSet {
            guard !mockMode, !isLoading, !importInProgress, !syncApplyInProgress else { return }
            #if os(macOS)
            MCPExportService.shared.exportProjects(store: self)
            #endif
        }
    }

    var folders: [ProjectFolder] = [] {
        didSet {
            guard !mockMode, !isLoading, !importInProgress, !syncApplyInProgress else { return }
            #if os(macOS)
            MCPExportService.shared.exportProjects(store: self)
            #endif
        }
    }

    var requests: [Request] = [] {
        didSet {
            guard !mockMode, !isLoading, !importInProgress, !syncApplyInProgress else { return }
            #if os(macOS)
            MCPExportService.shared.exportProjects(store: self)
            #endif
        }
    }

    var requestFolders: [RequestFolder] = [] {
        didSet {
            guard !mockMode, !isLoading, !importInProgress, !syncApplyInProgress else { return }
            #if os(macOS)
            MCPExportService.shared.exportProjects(store: self)
            #endif
        }
    }

    var environments: [ApiEnvironment] = [] {
        didSet {
            guard !mockMode, !isLoading, !importInProgress, !syncApplyInProgress else { return }
            #if os(macOS)
            MCPExportService.shared.exportEnvironments(environments: environments)
            #endif
        }
    }

    var specDocuments: [SpecDocument] = []
    var protoBundles: [ProtoBundle] = []

    private init() {
        self.mockMode = false
        setupStorage()
        load()
        if !StorageEnvironment.isScreenshotMode && !StorageEnvironment.isRunningTests {
            Task { @MainActor in
                CloudSyncService.shared.start()
            }
        }
    }

    static func mock(
        projects: [Project] = [],
        folders: [ProjectFolder] = [],
        requests: [Request] = [],
        requestFolders: [RequestFolder] = [],
        specDocuments: [SpecDocument] = [],
        protoBundles: [ProtoBundle] = []
    ) -> ProjectStore {
        let store = ProjectStore(mockMode: true)
        store.projects = projects
        store.folders = folders
        store.requests = requests
        store.requestFolders = requestFolders
        store.specDocuments = specDocuments
        store.protoBundles = protoBundles
        return store
    }

    private init(mockMode: Bool) {
        self.mockMode = mockMode
    }

    private func setupStorage() {
        if StorageEnvironment.isScreenshotMode || StorageEnvironment.isRunningTests {
            return
        }
        #if os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterBackground),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        #else
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        #endif
    }

    /// Hard-resets all data by clearing arrays and removing UserDefaults keys.
    /// Used only for remote zone deletion (external event). For user-initiated reset, use `softDeleteAll()`.
    func resetAllData() {
        for key in [
            Self.projectsKey,
            Self.foldersKey,
            Self.requestsKey,
            Self.requestFoldersKey,
            Self.environmentsKey,
            Self.specDocumentsKey,
            Self.protoBundlesKey,
        ] {
            storage.removeObject(forKey: key)
        }

        RequestLibraryPersistence.deleteAll()

        UIStateStore.shared.resetAll()

        isLoading = true
        projects = []
        folders = []
        requests = []
        requestFolders = []
        environments = []
        specDocuments = []
        protoBundles = []
        isLoading = false
    }

    /// Linked spec project is read-only when spec bytes are missing and re-fetch has not hydrated them.
    func isSpecProjectReadOnly(projectId: UUID) -> Bool {
        guard let project = projects.first(where: { $0.id == projectId }),
              let specLink = project.specLink,
              !specLink.isDetached else {
            return false
        }
        if let document = specDocuments.first(where: { $0.projectId == projectId }) {
            return document.isReadOnlyDueToMissingAsset
        }
        return !SpecDocument.hasLocalSpecBytes(projectId: projectId)
    }
}
