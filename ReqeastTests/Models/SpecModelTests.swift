//
//  SpecModelTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("Spec Model")
struct SpecModelTests {

    // MARK: - SpecOperationIdentity

    @Test func specOperationIdentityRoundTrip() throws {
        let identity = SpecOperationIdentity(
            primaryKey: "GET /pets",
            alternateKeys: ["listPets", "findPets"]
        )
        let decoded = try roundTrip(identity)
        #expect(decoded.primaryKey == "GET /pets")
        #expect(decoded.alternateKeys == ["listPets", "findPets"])
    }

    @Test func specOperationIdentityMissingAlternateKeysDefaultsToEmpty() throws {
        let json = """
        {"primaryKey": "POST /pets"}
        """
        let identity = try JSONDecoder().decode(SpecOperationIdentity.self, from: Data(json.utf8))
        #expect(identity.primaryKey == "POST /pets")
        #expect(identity.alternateKeys.isEmpty)
    }

    // MARK: - SpecLink

    @Test func specLinkRoundTrip() throws {
        let importedAt = Date(timeIntervalSinceReferenceDate: 1000)
        let link = SpecLink(
            format: .openapi,
            source: .file,
            contentFingerprint: "abc123",
            importedAt: importedAt,
            sourceURL: "https://api.example.com/openapi.yaml",
            specRevision: 2,
            isDetached: true
        )
        let decoded = try roundTrip(link)
        #expect(decoded.format == .openapi)
        #expect(decoded.source == .file)
        #expect(decoded.contentFingerprint == "abc123")
        #expect(decoded.importedAt == importedAt)
        #expect(decoded.sourceURL == "https://api.example.com/openapi.yaml")
        #expect(decoded.specRevision == 2)
        #expect(decoded.isDetached == true)
        #expect(decoded.gitRef == nil)
        #expect(decoded.backgroundCheckEnabled == false)
    }

    @Test func specLinkMissingOptionalFieldsUseDefaults() throws {
        let json = """
        {
            "format": "openapi",
            "source": "url",
            "contentFingerprint": "deadbeef",
            "importedAt": 1000
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let link = try decoder.decode(SpecLink.self, from: Data(json.utf8))
        #expect(link.specRevision == 0)
        #expect(link.isDetached == true)
        #expect(link.sourceURL == nil)
        #expect(link.lastCheckedAt == nil)
        #expect(link.lastSyncedAt == nil)
        #expect(link.backgroundCheckEnabled == false)
    }

    // MARK: - Project backward compatibility

    @Test func projectWithoutSpecLinkDefaultsToNil() throws {
        let json = """
        {"id": "00000000-0000-0000-0000-000000000001", "name": "Test", "color": "red", "createdAt": 1000, "updatedAt": 2000}
        """
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.specLink == nil)
    }

    @Test func projectWithSpecLinkRoundTrip() throws {
        var project = Project(name: "Petstore")
        project.specLink = SpecLink(
            format: .openapi,
            source: .paste,
            contentFingerprint: "fingerprint",
            importedAt: Date(timeIntervalSinceReferenceDate: 500)
        )
        let decoded = try roundTrip(project)
        #expect(decoded.specLink?.format == .openapi)
        #expect(decoded.specLink?.source == .paste)
        #expect(decoded.specLink?.contentFingerprint == "fingerprint")
    }

    // MARK: - Request backward compatibility

    @Test func requestWithoutSpecFieldsUsesDefaults() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "projectId": "00000000-0000-0000-0000-000000000002",
          "name": "Fetch",
          "type": "http",
          "sortOrder": 0,
          "createdAt": 1000,
          "updatedAt": 2000
        }
        """
        let request = try JSONDecoder().decode(Request.self, from: Data(json.utf8))
        #expect(request.specIdentity == nil)
        #expect(request.specLastSyncedAt == nil)
        #expect(request.isSpecStale == false)
        #expect(request.specFieldFingerprint == nil)
        #expect(request.specSnapshotPayload == nil)
    }

    @Test func requestWithSpecFieldsRoundTrip() throws {
        var request = Request(projectId: UUID(), name: "List pets", type: .http)
        request.specIdentity = SpecOperationIdentity(primaryKey: "listPets")
        request.specLastSyncedAt = Date(timeIntervalSinceReferenceDate: 3000)
        request.isSpecStale = true
        request.specFieldFingerprint = "field-fp"
        request.specSnapshotPayload = Data("snapshot".utf8)

        let decoded = try roundTrip(request)
        #expect(decoded.specIdentity?.primaryKey == "listPets")
        #expect(decoded.specLastSyncedAt == Date(timeIntervalSinceReferenceDate: 3000))
        #expect(decoded.isSpecStale == true)
        #expect(decoded.specFieldFingerprint == "field-fp")
        #expect(decoded.specSnapshotPayload == Data("snapshot".utf8))
    }

    // MARK: - SpecOperationSnapshot

    @Test func specKeyValueRoundTrip() throws {
        let value = SpecKeyValue(key: "limit", value: "10", enabled: true)
        let decoded = try roundTrip(value)
        #expect(decoded.key == "limit")
        #expect(decoded.enabled)
    }

    @Test func specBodySnapshotRoundTrip() throws {
        let bodies: [SpecBodySnapshot] = [
            .none,
            .json(content: "{}"),
            .urlencoded(fields: [SpecKeyValue(key: "q", value: "1", enabled: true)]),
            .formData(entries: [
                SpecFormDataEntry(
                    key: "file",
                    value: "",
                    enabled: true,
                    fieldType: .file,
                    fileName: "a.png",
                    mimeType: "image/png"
                ),
            ]),
            .raw(content: "ok", contentType: "text/plain"),
            .binary(fileName: "blob.bin"),
        ]

        for body in bodies {
            _ = try roundTrip(body)
        }
    }

    // MARK: - Helpers

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: encoded)
        #expect(decoded == value)
        return decoded
    }
}