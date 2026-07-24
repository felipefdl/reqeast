//
//  ProjectCodableTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("Project Codable")
struct ProjectCodableTests {
    @Test func backwardCompatMissingColorDefaultsToGray() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "name": "Legacy Project",
            "createdAt": 0,
            "updatedAt": 0
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let project = try decoder.decode(Project.self, from: Data(json.utf8))
        #expect(project.color == .gray)
    }

    @Test func codableRoundtripWithAllFields() throws {
        let folderId = UUID()
        let project = Project(
            name: "My API",
            emoji: "🚀",
            iconURL: "https://example.com/icon.png",
            color: .blue,
            folderId: folderId
        )

        let encoded = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: encoded)

        #expect(decoded.id == project.id)
        #expect(decoded.name == "My API")
        #expect(decoded.emoji == "🚀")
        #expect(decoded.iconURL == "https://example.com/icon.png")
        #expect(decoded.color == .blue)
        #expect(decoded.folderId == folderId)
    }

    @Test func folderColorLocalizedNamesAreNonEmpty() {
        for color in FolderColor.allCases {
            #expect(!color.localizedName.isEmpty, "FolderColor.\(color.rawValue) localizedName should not be empty")
        }
    }
}
