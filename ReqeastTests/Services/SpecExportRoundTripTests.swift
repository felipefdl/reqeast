//
//  SpecExportRoundTripTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

private enum RoundTripFixtures {
    static let petstore = ["petstore-2.0", "petstore-3.0", "petstore-3.1"]
    static let postman = ["postman-nested", "postman-vars"]
}

@Suite("SpecExportRoundTrip", .serialized)
struct SpecExportRoundTripTests {

    static let fixturesDirectory: URL = {
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            return URL(fileURLWithPath: srcRoot, isDirectory: true)
                .appendingPathComponent("ReqeastTests/Fixtures/SpecImport", isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SpecImport", isDirectory: true)
    }()

    // MARK: - AC19 OpenAPI round-trip

    @Test(arguments: RoundTripFixtures.petstore)
    @MainActor func petstoreOpenApiRoundTripAC19(fixture: String) async throws {
        let imported = try parseFixture(named: fixture, preferJSON: false)
        let store = try await committedStore(fixture: fixture, preferJSON: false)
        let project = try #require(store.projects.first)

        let exported = try await SpecExportService.exportData(
            project: project,
            store: store,
            kind: .openapi,
            options: SpecExportOptions.default
        )

        let roundtrip = try parseSpec(
            bytes: exported,
            sourceHint: .yaml,
            bundleEntryPath: nil,
            options: SpecParseOptions()
        )

        assertRoundTripParity(
            imported: imported.project,
            roundtrip: roundtrip.project,
            label: "AC19 OpenAPI \(fixture)"
        )
    }

    // MARK: - AC20 Postman round-trip

    @Test(arguments: RoundTripFixtures.postman)
    @MainActor func postmanRoundTripAC20(fixture: String) async throws {
        let imported = try parseFixture(named: fixture, preferJSON: true)
        let store = try await committedStore(fixture: fixture, preferJSON: true)
        let project = try #require(store.projects.first)

        let exported = try await SpecExportService.exportData(
            project: project,
            store: store,
            kind: .postman,
            options: SpecExportOptions.default
        )

        let roundtrip = try parseSpec(
            bytes: exported,
            sourceHint: .postman,
            bundleEntryPath: nil,
            options: SpecParseOptions()
        )

        assertRoundTripParity(
            imported: imported.project,
            roundtrip: roundtrip.project,
            label: "AC20 Postman \(fixture)"
        )
    }

    // MARK: - Helpers

    /// Compares semantic IR parity after Swift store → export → re-parse.
    /// Export omits some metadata (description, version) and may reshape folder
    /// hierarchy / body candidates; operations and environments must match.
    private func assertRoundTripParity(
        imported: NormalizedProject,
        roundtrip: NormalizedProject,
        label: String
    ) {
        let lhs = normalizedRoundTripProject(imported)
        let rhs = normalizedRoundTripProject(roundtrip)

        #expect(lhs.title == rhs.title, "\(label): title mismatch")
        #expect(lhs.environments == rhs.environments, "\(label): environments mismatch")
        #expect(lhs.folders == rhs.folders, "\(label): folders mismatch")
        #expect(lhs.operations == rhs.operations, "\(label): operations mismatch")
    }

    private func normalizedRoundTripProject(_ project: NormalizedProject) -> NormalizedProject {
        let folderNameById = Dictionary(uniqueKeysWithValues: project.folders.map { ($0.id, $0.name) })

        let folderNames = project.folders.map(\.name).sorted()
        let folders = folderNames.enumerated().map { index, name in
            NormalizedFolder(
                id: name,
                parentId: nil,
                name: name,
                sortHint: UInt32(index)
            )
        }

        let operations = project.operations
            .sorted { $0.primaryKey < $1.primaryKey }
            .map { operation in
                var copy = operation
                copy.folderId = operation.folderId.flatMap { folderNameById[$0] }
                copy.bodyCandidates = []
                copy.parameters = operation.parameters.map { parameter in
                    var normalized = parameter
                    normalized.valueSource = .missing
                    return normalized
                }
                return copy
            }

        return NormalizedProject(
            title: project.title,
            description: nil,
            version: nil,
            iconUrl: project.iconUrl,
            securitySchemes: project.securitySchemes,
            folders: folders,
            operations: operations,
            environments: project.environments.sorted { $0.name < $1.name }
        )
    }

    @MainActor
    private func committedStore(fixture: String, preferJSON: Bool) async throws -> ProjectStore {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-roundtrip-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let bytes = try fixtureBytes(named: fixture, preferJSON: preferJSON)
        let hint = sourceHint(for: fixture, preferJSON: preferJSON)

        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: hint,
            source: .file,
            options: SpecImportOptions.default
        )

        let store = ProjectStore.mock()
        try SpecImportService.commit(preview: preview, to: store)
        return store
    }

    private func parseFixture(named name: String, preferJSON: Bool) throws -> SpecImportResult {
        let bytes = try fixtureBytes(named: name, preferJSON: preferJSON)
        let hint = sourceHint(for: name, preferJSON: preferJSON)
        return try parseSpec(
            bytes: bytes,
            sourceHint: hint,
            bundleEntryPath: nil,
            options: SpecParseOptions()
        )
    }

    private func sourceHint(for fixture: String, preferJSON: Bool) -> SpecSourceHint {
        if fixture.hasPrefix("postman-") {
            return .postman
        }
        return preferJSON ? .json : .yaml
    }

    private func fixtureBytes(named name: String, preferJSON: Bool) throws -> Data {
        let yamlURL = Self.fixturesDirectory.appendingPathComponent("\(name).input.yaml")
        let jsonURL = Self.fixturesDirectory.appendingPathComponent("\(name).input.json")

        let url: URL
        if preferJSON, FileManager.default.fileExists(atPath: jsonURL.path) {
            url = jsonURL
        } else if FileManager.default.fileExists(atPath: yamlURL.path) {
            url = yamlURL
        } else if FileManager.default.fileExists(atPath: jsonURL.path) {
            url = jsonURL
        } else {
            throw FixtureError.missingInput(name)
        }
        return try Data(contentsOf: url)
    }

    private enum FixtureError: Error {
        case missingInput(String)
    }
}