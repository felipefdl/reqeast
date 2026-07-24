//
//  SpecOperationSnapshot.swift
//  Reqeast
//

import Foundation

/// Key-based parameter/header row for spec snapshots (no per-row UUID).
struct SpecKeyValue: Codable, Hashable {
    var key: String
    var value: String
    var enabled: Bool
}

/// Multipart form field captured in a spec snapshot.
struct SpecFormDataEntry: Codable, Hashable {
    var key: String
    var value: String
    var enabled: Bool
    var fieldType: FormDataFieldType
    var fileName: String
    var mimeType: String
}

/// Request body state owned by the linked spec (Rule A).
enum SpecBodySnapshot: Codable, Hashable {
    case none
    case json(content: String)
    case urlencoded(fields: [SpecKeyValue])
    case formData(entries: [SpecFormDataEntry])
    case raw(content: String, contentType: String)
    case binary(fileName: String)
}

/// Per-request spec field baseline stored on disk and synced via `specSnapshotPayload`.
struct SpecOperationSnapshot: Codable, Hashable {
    var method: String
    var urlTemplate: String
    var params: [SpecKeyValue]
    var headers: [SpecKeyValue]
    var body: SpecBodySnapshot
}