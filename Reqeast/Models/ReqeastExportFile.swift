//
//  ReqeastExportFile.swift
//  Reqeast
//

import SwiftUI
import UniformTypeIdentifiers

struct ReqeastExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.reqeastExport] }

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
