//
//  JqFilterHelpSection.swift
//  Reqeast
//

import Foundation

struct JqFilterHelpSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [JqFilterHelpItem]

    struct JqFilterHelpItem: Identifiable {
        let id = UUID()
        let expression: String
        let description: String
    }
}

extension JqFilterHelpSection {
    static let all: [JqFilterHelpSection] = [
        JqFilterHelpSection(title: String(localized: "Basics"), items: [
            .init(expression: ".", description: String(localized: "Full object")),
            .init(expression: ".key", description: String(localized: "Object field")),
            .init(expression: ".key.nested", description: String(localized: "Nested field")),
            .init(expression: ".[]", description: String(localized: "All elements")),
            .init(expression: ".[0]", description: String(localized: "Array index")),
            .init(expression: ".[0:3]", description: String(localized: "Array slice")),
        ]),
        JqFilterHelpSection(title: String(localized: "Filtering & Mapping"), items: [
            .init(expression: ".[] | select(.x < 10)", description: String(localized: "Filter elements")),
            .init(expression: ".[] | .name", description: String(localized: "Map to field")),
            .init(expression: "map(.name)", description: String(localized: "Map array")),
            .init(expression: "[.[] | .name]", description: String(localized: "Collect into array")),
            .init(expression: "first(.[])  last(.[])", description: String(localized: "First / last element")),
            .init(expression: "{name, age}", description: String(localized: "Pick fields")),
            .init(expression: "del(.key)", description: String(localized: "Remove field")),
        ]),
        JqFilterHelpSection(title: String(localized: "Aggregation"), items: [
            .init(expression: "length", description: String(localized: "Array / string length")),
            .init(expression: "keys", description: String(localized: "Object keys")),
            .init(expression: "add", description: String(localized: "Sum / concatenate")),
            .init(expression: "sort_by(.name)", description: String(localized: "Sort array")),
            .init(expression: "group_by(.type)", description: String(localized: "Group by field")),
            .init(expression: "unique_by(.id)", description: String(localized: "Deduplicate")),
        ]),
        JqFilterHelpSection(title: String(localized: "Types & Conversion"), items: [
            .init(expression: "type", description: String(localized: "Value type")),
            .init(expression: "tostring", description: String(localized: "Convert to string")),
            .init(expression: ".data | fromjson", description: String(localized: "Parse JSON string")),
            .init(expression: "@base64d", description: String(localized: "Base64 decode")),
            .init(expression: ".x // \"default\"", description: String(localized: "Default value")),
        ]),
        JqFilterHelpSection(title: String(localized: "Testing"), items: [
            .init(expression: "has(\"key\")", description: String(localized: "Key exists")),
            .init(expression: "test(\"regex\")", description: String(localized: "Regex match")),
            .init(expression: "not", description: String(localized: "Negate")),
            .init(expression: "to_entries", description: String(localized: "Key-value pairs")),
        ]),
    ]
}
