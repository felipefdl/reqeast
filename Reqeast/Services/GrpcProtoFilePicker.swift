//
//  GrpcProtoFilePicker.swift
//  Reqeast
//

import Foundation
import UniformTypeIdentifiers

enum GrpcProtoImportHelpers {
    static let protoTypes: [UTType] = {
        if let proto = UTType(filenameExtension: "proto") {
            return [proto]
        }
        return [.plainText, .data]
    }()
}

#if os(macOS)
import AppKit

enum GrpcProtoFilePicker {
    static func chooseProtoFiles(completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Proto Files")
        panel.prompt = String(localized: "Choose")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = GrpcProtoImportHelpers.protoTypes
        panel.begin { response in
            completion(response == .OK ? panel.urls : [])
        }
    }
}
#endif