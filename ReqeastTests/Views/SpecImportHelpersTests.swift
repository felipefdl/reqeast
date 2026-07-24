//
//  SpecImportHelpersTests.swift
//  ReqeastTests
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Reqeast

@Suite("SpecImportHelpers")
struct SpecImportHelpersTests {

    @Test func detectsPostmanCollectionFromSchema() {
        let json = """
        {
          "info": {
            "name": "Sample",
            "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
          },
          "item": []
        }
        """
        let data = Data(json.utf8)

        #expect(SpecImportHelpers.isPostmanCollection(data))
        #expect(SpecImportHelpers.sourceHint(for: data) == .postman)
        #expect(SpecImportHelpers.detectedFormat(bytes: data, sourceHint: .json) == .postman)
    }

    @Test func detectsHarLogFromVersionAndEntries() {
        let json = """
        {
          "log": {
            "version": "1.2",
            "entries": []
          }
        }
        """
        let data = Data(json.utf8)

        #expect(SpecImportHelpers.isHarLog(data))
        #expect(SpecImportHelpers.sourceHint(for: data) == .har)
        #expect(SpecImportHelpers.detectedFormat(bytes: data, sourceHint: .json) == .har)
    }

    @Test func openApiJsonIsNotPostman() {
        let json = """
        {"openapi":"3.0.0","info":{"title":"Petstore","version":"1.0.0"},"paths":{}}
        """
        let data = Data(json.utf8)

        #expect(!SpecImportHelpers.isPostmanCollection(data))
        #expect(SpecImportHelpers.sourceHint(for: data) == .json)
        #expect(SpecImportHelpers.detectedFormat(bytes: data, sourceHint: .json) == .openapi)
    }

    @Test func importTargetIsNeverLockedAfterMergeSupport() {
        #expect(!SpecImportHelpers.locksImportTargetToNewProject(.postman))
        #expect(!SpecImportHelpers.locksImportTargetToNewProject(.openapi))
    }

    @Test func optionsSummaryIncludesLinkToSpecPreference() {
        var options = SpecImportOptions.default
        options.linkToSpec = .linked
        #expect(SpecImportHelpers.optionsSummary(options).contains("Yes"))

        options.linkToSpec = .detached
        #expect(SpecImportHelpers.optionsSummary(options).contains("Detached"))
    }

    @Test func specFileTypesIncludeM6ImportExtensions() {
        let extensions = Set(
            SpecImportHelpers.specFileTypes.compactMap(\.preferredFilenameExtension)
        )
        // yaml/yml share a UTType on Apple platforms (preferred extension is usually `yml`).
        #expect(extensions.contains("yml"))
        #expect(extensions.contains("json"))
        #expect(extensions.contains("har"))
        #expect(extensions.contains("graphql"))
        #expect(extensions.contains("gql"))
        #expect(SpecImportHelpers.specFileTypes.count == 6)

        for ext in ["yaml", "yml", "json", "har", "graphql", "gql"] {
            let fileType = UTType(filenameExtension: ext)
            #expect(fileType != nil, "Expected UTType for .\(ext)")
            let allowed = SpecImportHelpers.specFileTypes.contains { specType in
                guard let fileType else { return false }
                return specType == fileType || fileType.conforms(to: specType)
            }
            #expect(allowed, "fileImporter should allow .\(ext)")
        }
    }

    @Test func findBundleEntryPrefersOpenApiYaml() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-bundle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try Data("paths: {}".utf8).write(to: tempDir.appendingPathComponent("openapi.yaml"))
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("openapi.json"))

        let entry = SpecImportHelpers.findBundleEntry(in: tempDir)
        #expect(entry?.lastPathComponent == "openapi.yaml")
    }

    @Test func findBundleEntryDiscoversSingleOpenApiSuffixFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-bundle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("account-service.openapi.json"))

        let entry = SpecImportHelpers.findBundleEntry(in: tempDir)
        #expect(entry?.lastPathComponent == "account-service.openapi.json")
    }

    @Test func findBundleEntryRejectsAmbiguousOpenApiSuffixFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-bundle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("alpha.openapi.json"))
        try Data("{}".utf8).write(to: tempDir.appendingPathComponent("beta.openapi.json"))

        #expect(SpecImportHelpers.findBundleEntry(in: tempDir) == nil)
    }

    @Test func defaultBaseURLVariableNameUsesFileStem() {
        var used: Set<String> = []
        let name = SpecImportHelpers.defaultBaseURLVariableName(
            fileName: "account-service.openapi.json",
            fallbackTitle: "IoT Account Service API",
            usedNames: &used
        )
        #expect(name == "account_service_base_url")
    }

    @Test func defaultBaseURLVariableNameDedupesCollisions() {
        var used: Set<String> = []
        let first = SpecImportHelpers.defaultBaseURLVariableName(
            fileName: "alpha.openapi.json",
            fallbackTitle: "Alpha",
            usedNames: &used
        )
        let second = SpecImportHelpers.defaultBaseURLVariableName(
            fileName: "alpha.openapi.yml",
            fallbackTitle: "Alpha Two",
            usedNames: &used
        )
        #expect(first == "alpha_base_url")
        #expect(second == "alpha_base_url_2")
    }

    @Test func slugStemStripsOpenApiSuffix() {
        #expect(SpecImportHelpers.slugStem(fromFileName: "account-service.openapi.json") == "account_service")
    }

    @Test func resolveBundleFolderTreatsMultipleOpenApiSuffixFilesAsMultiSpec() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-bundle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let alpha = tempDir.appendingPathComponent("alpha.openapi.json")
        let beta = tempDir.appendingPathComponent("beta.openapi.json")
        try Data("{}".utf8).write(to: alpha)
        try Data("{}".utf8).write(to: beta)

        let resolution = try #require(SpecImportHelpers.resolveBundleFolder(in: tempDir))
        guard case .multiSpec(let entries) = resolution else {
            Issue.record("Expected multiSpec resolution")
            return
        }
        #expect(entries.map(\.lastPathComponent) == ["alpha.openapi.json", "beta.openapi.json"])
    }
}