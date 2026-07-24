//
//  RequestFolderTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("RequestFolder Model")
struct RequestFolderTests {
    @Test func requestFolderInit() {
        let projectId = UUID()
        let folder = RequestFolder(projectId: projectId, name: "Auth", color: .red)
        #expect(folder.name == "Auth")
        #expect(folder.projectId == projectId)
        #expect(folder.color == .red)
    }

    @Test func requestFolderDefaultColor() {
        let folder = RequestFolder(projectId: UUID(), name: "Test")
        #expect(folder.color == .blue)
    }

    @Test func requestFolderCodable() throws {
        let folder = RequestFolder(projectId: UUID(), name: "Users", color: .green)
        let data = try JSONEncoder().encode(folder)
        let decoded = try JSONDecoder().decode(RequestFolder.self, from: data)
        #expect(decoded.id == folder.id)
        #expect(decoded.projectId == folder.projectId)
        #expect(decoded.name == folder.name)
        #expect(decoded.color == folder.color)
    }

    @Test func requestFolderIsHashable() {
        let f1 = RequestFolder(projectId: UUID(), name: "A")
        let f2 = RequestFolder(projectId: UUID(), name: "B")
        let set: Set<RequestFolder> = [f1, f2]
        #expect(set.count == 2)
    }
}
