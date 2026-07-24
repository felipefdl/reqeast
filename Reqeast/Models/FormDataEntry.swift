//
//  FormDataEntry.swift
//  Reqeast
//

import Foundation

enum FormDataFieldType: String, Codable, Hashable {
    case text
    case file
}

struct FormDataEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var key: String
    var value: String
    var enabled: Bool
    var fieldType: FormDataFieldType
    var fileName: String
    var mimeType: String

    init(
        id: UUID = UUID(),
        key: String = "",
        value: String = "",
        enabled: Bool = true,
        fieldType: FormDataFieldType = .text,
        fileName: String = "",
        mimeType: String = ""
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.enabled = enabled
        self.fieldType = fieldType
        self.fileName = fileName
        self.mimeType = mimeType
    }

    var isEmpty: Bool {
        key.isEmpty && value.isEmpty && fileName.isEmpty
    }
}
