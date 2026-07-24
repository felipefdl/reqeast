//
//  SpecOperationIdentity.swift
//  Reqeast
//

import Foundation

/// Stable spec operation identity for sync matching. `Request.id` never changes.
struct SpecOperationIdentity: Codable, Hashable {
    /// `operationId` or normalized `METHOD /path` (uppercase method, no query).
    var primaryKey: String
    /// Previous `operationId` values or old METHOD/path after spec renames.
    var alternateKeys: [String]

    init(primaryKey: String, alternateKeys: [String] = []) {
        self.primaryKey = primaryKey
        self.alternateKeys = alternateKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryKey = try container.decode(String.self, forKey: .primaryKey)
        alternateKeys = try container.decodeIfPresent([String].self, forKey: .alternateKeys) ?? []
    }
}