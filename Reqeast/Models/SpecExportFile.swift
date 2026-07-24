//
//  SpecExportFile.swift
//  Reqeast
//

import SwiftUI
import UniformTypeIdentifiers

struct SpecExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .yaml] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}