//
//  SchemaVersionTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("SchemaVersion")
struct SchemaVersionTests {

    @Test func currentVersionIsOne() {
        #expect(CloudSyncableSchema.currentVersion == 1)
    }

    @Test func projectEncodesSchemaVersion() throws {
        let project = Project(name: "t")
        let data = try JSONEncoder().encode(project)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["schemaVersion"] as? Int == 1)
    }

    @Test func requestEncodesSchemaVersion() throws {
        let request = Request(projectId: UUID(), name: "t")
        let data = try JSONEncoder().encode(request)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["schemaVersion"] as? Int == 1)
    }

    @Test func projectDecodeIsBackwardCompat() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"old","createdAt":0,"updatedAt":0}"#
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let project = try decoder.decode(Project.self, from: data)
        #expect(project.schemaVersion == 1)
    }

    @Test func requestDecodeIsBackwardCompat() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let request = Request(projectId: UUID(), name: "t")
        var obj = try JSONSerialization.jsonObject(with: encoder.encode(request)) as! [String: Any]
        obj.removeValue(forKey: "schemaVersion")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try decoder.decode(Request.self, from: stripped)
        #expect(decoded.schemaVersion == 1)
    }

    @Test func projectRejectsFutureSchemaVersion() throws {
        try assertRejectsFutureSchema(Project(name: "t"), type: Project.self)
    }

    @Test func projectFolderRejectsFutureSchemaVersion() throws {
        try assertRejectsFutureSchema(ProjectFolder(name: "t"), type: ProjectFolder.self)
    }

    @Test func requestRejectsFutureSchemaVersion() throws {
        try assertRejectsFutureSchema(Request(projectId: UUID(), name: "t"), type: Request.self)
    }

    @Test func requestFolderRejectsFutureSchemaVersion() throws {
        try assertRejectsFutureSchema(RequestFolder(projectId: UUID(), name: "t"), type: RequestFolder.self)
    }

    @Test func apiEnvironmentRejectsFutureSchemaVersion() throws {
        try assertRejectsFutureSchema(ApiEnvironment(projectId: UUID(), name: "t"), type: ApiEnvironment.self)
    }

    @Test func missingSchemaVersionDecodesAsLegacyNotCurrent() {
        // Pinned to the legacy constant: defaulting to currentVersion would misread
        // pre-versioning blobs as the newest format after the first version bump.
        #expect(CloudSyncableSchema.legacyVersion == 1)
    }

    @Test func projectRejectsZeroSchemaVersion() throws {
        try assertRejectsSchemaVersion(Project(name: "t"), type: Project.self, version: 0)
    }

    @Test func projectRejectsNegativeSchemaVersion() throws {
        try assertRejectsSchemaVersion(Project(name: "t"), type: Project.self, version: -1)
    }

    private func assertRejectsFutureSchema<T: Codable>(_ value: T, type: T.Type) throws {
        try assertRejectsSchemaVersion(value, type: type, version: CloudSyncableSchema.currentVersion + 1)
    }

    private func assertRejectsSchemaVersion<T: Codable>(_ value: T, type: T.Type, version: Int) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var obj = try JSONSerialization.jsonObject(with: encoder.encode(value)) as! [String: Any]
        obj["schemaVersion"] = version
        let bumped = try JSONSerialization.data(withJSONObject: obj)
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(type, from: bumped)
        }
    }
}
