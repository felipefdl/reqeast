//
//  SpecImportFilePicker.swift
//  Reqeast
//

import Foundation
import UniformTypeIdentifiers

#if os(macOS)
import AppKit

enum SpecImportFilePicker {
    static func chooseFile(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Spec File")
        panel.prompt = String(localized: "Choose")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = SpecImportHelpers.specFileTypes
        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }

    static func chooseFolder(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Spec Folder")
        panel.prompt = String(localized: "Choose")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = SpecImportHelpers.specFolderTypes
        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }
}
#endif