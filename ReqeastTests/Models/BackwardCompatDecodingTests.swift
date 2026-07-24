//
//  BackwardCompatDecodingTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("Backward-Compat Decoding")
struct BackwardCompatDecodingTests {

    @Test func projectFolderWithoutTimestamps() throws {
        let json = """
        {"id": "00000000-0000-0000-0000-000000000001", "name": "APIs"}
        """
        let folder = try JSONDecoder().decode(ProjectFolder.self, from: Data(json.utf8))
        #expect(folder.name == "APIs")
        #expect(folder.createdAt == .distantPast)
        #expect(folder.updatedAt == .distantPast)
        #expect(folder.color == .gray)
    }

    @Test func projectFolderWithTimestamps() throws {
        let json = """
        {"id": "00000000-0000-0000-0000-000000000001", "name": "APIs", "color": "blue", "createdAt": 1000, "updatedAt": 2000}
        """
        let folder = try JSONDecoder().decode(ProjectFolder.self, from: Data(json.utf8))
        #expect(folder.name == "APIs")
        #expect(folder.color == .blue)
        #expect(folder.createdAt == Date(timeIntervalSinceReferenceDate: 1000))
        #expect(folder.updatedAt == Date(timeIntervalSinceReferenceDate: 2000))
    }

    @Test func projectFolderRoundTrip() throws {
        let original = ProjectFolder(name: "Test", color: .green)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectFolder.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.color == original.color)
        #expect(decoded.createdAt == original.createdAt)
        #expect(decoded.updatedAt == original.updatedAt)
    }

    @Test func apiEnvironmentWithoutTimestamps() throws {
        let json = """
        {"id": "00000000-0000-0000-0000-000000000001", "projectId": "00000000-0000-0000-0000-000000000002", "name": "Dev", "variables": [], "isActive": true}
        """
        let env = try JSONDecoder().decode(ApiEnvironment.self, from: Data(json.utf8))
        #expect(env.name == "Dev")
        #expect(env.createdAt == .distantPast)
        #expect(env.updatedAt == .distantPast)
    }

    @Test func apiEnvironmentWithTimestamps() throws {
        let json = """
        {"id": "00000000-0000-0000-0000-000000000001", "projectId": "00000000-0000-0000-0000-000000000002", "name": "Dev", "variables": [], "isActive": true, "createdAt": 1000, "updatedAt": 2000}
        """
        let env = try JSONDecoder().decode(ApiEnvironment.self, from: Data(json.utf8))
        #expect(env.createdAt == Date(timeIntervalSinceReferenceDate: 1000))
        #expect(env.updatedAt == Date(timeIntervalSinceReferenceDate: 2000))
    }

    @Test func apiEnvironmentRoundTrip() throws {
        let original = ApiEnvironment(projectId: UUID(), name: "Prod", variables: [
            EnvironmentVariable(key: "host", value: "example.com"),
        ], isActive: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ApiEnvironment.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.createdAt == original.createdAt)
        #expect(decoded.updatedAt == original.updatedAt)
    }

    @Test func projectWithoutDeletedAt() throws {
        let json = """
        {"id": "00000000-0000-0000-0000-000000000001", "name": "Test", "color": "red", "createdAt": 1000, "updatedAt": 2000}
        """
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.name == "Test")
        #expect(project.deletedAt == nil)
    }

    @Test func projectWithDeletedAt() throws {
        let json = """
        {"id": "00000000-0000-0000-0000-000000000001", "name": "Test", "color": "red", "createdAt": 1000, "updatedAt": 2000, "deletedAt": 3000}
        """
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.deletedAt == Date(timeIntervalSinceReferenceDate: 3000))
    }

    @Test func requestWithoutIsRenamedOrDeletedAt() throws {
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
        #expect(request.name == "Fetch")
        #expect(!request.isRenamed, "Missing isRenamed must default to false for legacy records")
        #expect(request.deletedAt == nil)
    }

    @Test func requestFolderWithoutTimestamps() throws {
        let json = """
        {"id": "00000000-0000-0000-0000-000000000001", "projectId": "00000000-0000-0000-0000-000000000002", "name": "APIs"}
        """
        let folder = try JSONDecoder().decode(RequestFolder.self, from: Data(json.utf8))
        #expect(folder.name == "APIs")
        #expect(folder.deletedAt == nil)
    }
}
