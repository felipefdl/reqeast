//
//  SpecSyncService+Check.swift
//  Reqeast
//

import Foundation

enum SpecSyncCheckOutcome: Equatable {
    case upToDate
    case diff(SpecSyncDiff, newFingerprint: String, newBytes: Data)
}

enum SpecSyncBackgroundCheckOutcome: Equatable {
    case upToDate
    case updateAvailable
}

extension SpecSyncService {

    /// Projects the background scheduler may poll. Requires explicit per-project opt-in (AC28).
    static func projectsEligibleForBackgroundCheck(in store: ProjectStore) -> [Project] {
        store.projects.filter { project in
            guard project.deletedAt == nil,
                  let specLink = project.specLink,
                  specLink.backgroundCheckEnabled,
                  specLink.isEligibleForBackgroundCheck else {
                return false
            }
            return true
        }
    }

    /// Fingerprint-only background check. Never parses a diff or auto-applies changes (AC28).
    @MainActor
    static func backgroundFingerprintCheck(
        project: Project,
        store: ProjectStore
    ) async throws -> SpecSyncBackgroundCheckOutcome {
        guard let specLink = project.specLink else {
            throw SpecImportError.from(
                message: String(localized: "This project has no linked spec."),
                kind: .invalidSpec
            )
        }
        guard specLink.backgroundCheckEnabled else {
            return .upToDate
        }
        guard specLink.isEligibleForBackgroundCheck else {
            throw SpecImportError.from(
                message: String(localized: "This project is not linked to a live spec source."),
                kind: .invalidSpec
            )
        }

        #if DEBUG
        SpecSyncSchedulerTestSupport.recordFetch(projectId: project.id)
        #endif

        let (fetchedBytes, _) = try await fetchLinkedSpecBytes(
            specLink: specLink,
            projectId: project.id
        )
        let newFingerprint = canonicalFingerprint(resolvedBytes: fetchedBytes)

        updateLastChecked(projectId: project.id, store: store)

        if newFingerprint == specLink.contentFingerprint {
            return .upToDate
        }
        return .updateAvailable
    }

    @concurrent
    private static func parseNormalizedProject(
        bytes: Data,
        specLink: SpecLink,
        bundleEntryPath: String?
    ) async throws -> (NormalizedProject, String) {
        let sourceHint = sourceHint(for: specLink, bytes: bytes)
        let result = try parseSpec(
            bytes: bytes,
            sourceHint: sourceHint,
            bundleEntryPath: bundleEntryPath,
            options: SpecParseOptions()
        )
        return (result.project, result.contentFingerprint)
    }

    static func buildBindings(projectId: UUID, store: ProjectStore) -> [SpecOperationBinding] {
        store.requests(for: projectId).compactMap { request in
            guard let identity = request.specIdentity else { return nil }
            return SpecOperationBinding(
                requestId: request.id.uuidString,
                primaryKey: identity.primaryKey,
                alternateKeys: identity.alternateKeys
            )
        }
    }

    static func loadSpecBytes(projectId: UUID) throws -> (Data, String?) {
        let directory = SpecImportService.specsDirectory(for: projectId)
        let bundleDirectory = directory.appendingPathComponent("bundle", isDirectory: true)

        if FileManager.default.fileExists(atPath: bundleDirectory.path),
           let entryURL = SpecImportHelpers.findBundleEntry(in: bundleDirectory) {
            let data = try Data(contentsOf: entryURL)
            let relativePath = "bundle/\(entryURL.lastPathComponent)"
            return (data, relativePath)
        }

        for fileName in ["spec.yaml", "spec.json"] {
            let fileURL = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return (try Data(contentsOf: fileURL), nil)
            }
        }

        throw SpecImportError.from(
            message: String(localized: "Could not find the on-disk spec for this project."),
            kind: .invalidSpec
        )
    }

    @MainActor
    static func checkForUpdates(project: Project, store: ProjectStore) async throws -> SpecSyncCheckOutcome {
        guard let specLink = project.specLink else {
            throw SpecImportError.from(
                message: String(localized: "This project has no linked spec."),
                kind: .invalidSpec
            )
        }
        guard specLink.isEligibleForRemoteCheck else {
            throw SpecImportError.from(
                message: String(localized: "This project has no live spec source to compare."),
                kind: .invalidSpec
            )
        }
        let (fetchedBytes, fetchedBundleEntryPath) = try await fetchLinkedSpecBytes(
            specLink: specLink,
            projectId: project.id
        )
        let (newProject, newFingerprint) = try await parseNormalizedProject(
            bytes: fetchedBytes,
            specLink: specLink,
            bundleEntryPath: fetchedBundleEntryPath
        )

        updateLastChecked(projectId: project.id, store: store)

        if newFingerprint == specLink.contentFingerprint {
            return .upToDate
        }

        let (oldBytes, bundleEntryPath) = try loadSpecBytes(projectId: project.id)
        let (oldProject, _) = try await parseNormalizedProject(
            bytes: oldBytes,
            specLink: specLink,
            bundleEntryPath: bundleEntryPath
        )

        let bindings = buildBindings(projectId: project.id, store: store)
        var diff = try diffSpec(
            old: oldProject,
            new: newProject,
            bindings: bindings,
            options: DiffOptions()
        )
        diff = enrichDiffWithConflicts(diff, store: store)

        return .diff(diff, newFingerprint: newFingerprint, newBytes: fetchedBytes)
    }

    @MainActor
    private static func updateLastChecked(projectId: UUID, store: ProjectStore) {
        guard let index = store.projects.firstIndex(where: { $0.id == projectId }) else {
            return
        }
        var project = store.projects[index]
        var specLink = project.specLink
        specLink?.lastCheckedAt = Date()
        project.specLink = specLink
        project.touch()
        store.projects[index] = project
        store.saveLocal()
        CloudSyncService.shared.queueSave(project)
    }

    @MainActor
    private static func fetchLinkedSpecBytes(
        specLink: SpecLink,
        projectId: UUID
    ) async throws -> (Data, String?) {
        switch specLink.source {
        case .url:
            guard let sourceURL = specLink.sourceURL, let url = URL(string: sourceURL) else {
                throw SpecImportError.from(
                    message: String(localized: "This project is not linked to a live spec URL."),
                    kind: .invalidSpec
                )
            }
            #if DEBUG
            if let fixture = SpecSyncUITestSupport.fetchData(for: url) {
                return (fixture, nil)
            }
            #endif
            return (try await SafeFetchService.shared.fetch(url: url), nil)

        case .gitHTTPS, .gitProvider, .localBookmark:
            return try await fetchGitLinkedSpecBytes(specLink: specLink, projectId: projectId)

        case .file, .paste:
            throw SpecImportError.from(
                message: String(localized: "This project is not linked to a live spec source."),
                kind: .invalidSpec
            )
        }
    }

    @MainActor
    private static func fetchGitLinkedSpecBytes(
        specLink: SpecLink,
        projectId: UUID
    ) async throws -> (Data, String?) {
        #if DEBUG
        if let sourceURL = specLink.sourceURL,
           let url = URL(string: sourceURL),
           let fixture = SpecSyncUITestSupport.fetchData(for: url) {
            return (fixture, nil)
        }
        #endif

        switch specLink.source {
        case .localBookmark:
            let payload = try SpecBookmarkStore.readSpecBytes(projectId: projectId)
            return (payload.bytes, payload.bundleEntryPath)
        default:
            let bytes = try await GitSpecSourceService.fetchLinkedSpec(
                specLink: specLink,
                projectId: projectId
            )
            return (bytes, nil)
        }
    }

    private static func sourceHint(for specLink: SpecLink, bytes: Data) -> SpecSourceHint {
        switch specLink.format {
        case .postman:
            return .postman
        default:
            return SpecImportHelpers.sourceHint(for: bytes)
        }
    }
}