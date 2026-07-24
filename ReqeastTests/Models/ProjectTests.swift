//
//  ProjectTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("Project Model")
struct ProjectTests {
    @Test func projectInitSetsDefaults() {
        let project = Project(name: "Test")
        #expect(project.name == "Test")
        #expect(project.folderId == nil)
        #expect(project.id != UUID())
    }

    @Test func projectFolderInitSetsDefaults() {
        let folder = ProjectFolder(name: "API", color: .blue)
        #expect(folder.name == "API")
        #expect(folder.color == .blue)
    }

    @Test func folderColorHasAllCases() {
        #expect(FolderColor.allCases.count == 8)
    }

    @Test func projectIsHashable() {
        let p1 = Project(name: "A")
        let p2 = Project(name: "B")
        let set: Set<Project> = [p1, p2]
        #expect(set.count == 2)
    }
}
