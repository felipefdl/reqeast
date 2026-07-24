//
//  SpecExportHelpers.swift
//  Reqeast
//

import Foundation
import UniformTypeIdentifiers

enum SpecExportHelpers {

    static func contentType(for kind: SpecExportKind, options: SpecExportOptions) -> UTType {
        switch kind {
        case .openapi:
            switch options.openApiFormat {
            case .yaml: UTType(filenameExtension: "yaml") ?? .yaml
            case .json: .json
            }
        case .postman:
            .json
        }
    }

    static func summaryText(
        store: ProjectStore,
        project: Project,
        kind: SpecExportKind
    ) -> String {
        let httpCount = store.requests(for: project.id).filter { $0.type == .http }.count
        let environmentCount = store.environments(for: project.id).count

        var parts: [String] = []
        parts.append("\(httpCount) HTTP \(httpCount == 1 ? "request" : "requests")")
        if environmentCount > 0 {
            parts.append("\(environmentCount) \(environmentCount == 1 ? "environment" : "environments")")
        }
        if kind == .openapi {
            parts.append(String(localized: "OpenAPI 3.1"))
        } else {
            parts.append(String(localized: "Postman Collection v2.1"))
        }
        return parts.joined(separator: ", ")
    }
}