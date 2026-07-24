//
//  TemplateExtractor.swift
//  Reqeast
//

import Foundation

enum TemplateExtractor {
    private static let pattern = try! NSRegularExpression(pattern: #"\{\{([^}]+)\}\}"#)

    static func extractVariableNames(from input: String) -> Set<String> {
        let range = NSRange(location: 0, length: (input as NSString).length)
        let matches = pattern.matches(in: input, range: range)
        var names = Set<String>()
        for match in matches {
            if let keyRange = Range(match.range(at: 1), in: input) {
                names.insert(String(input[keyRange]))
            }
        }
        return names
    }

    static func allVariableNames(in request: Request) -> Set<String> {
        var names = Set<String>()

        func scan(_ value: String) {
            names.formUnion(extractVariableNames(from: value))
        }

        func scanEntries(_ entries: [KeyValueEntry]) {
            for entry in entries where entry.enabled {
                scan(entry.key)
                scan(entry.value)
            }
        }

        switch request.type {
        case .http:
            guard let data = request.httpData else { break }
            scan(data.url)
            scanEntries(data.headers)
            scanEntries(data.params)
            scan(data.bodyContent)
            scanEntries(data.bodyFormData)
            for entry in data.bodyFormDataEntries where entry.enabled && entry.fieldType == .text {
                scan(entry.key)
                scan(entry.value)
            }
            scan(data.authToken)
            scan(data.authUsername)
            scan(data.authPassword)
            scan(data.authApiKeyName)
            scan(data.authApiKeyValue)

        case .tcp:
            guard let data = request.tcpData else { break }
            scan(data.host)

        case .udp:
            guard let data = request.udpData else { break }
            scan(data.host)

        case .webSocket:
            guard let data = request.webSocketData else { break }
            scan(data.url)
            scanEntries(data.headers)

        case .sse:
            guard let data = request.sseData else { break }
            scan(data.url)
            scanEntries(data.headers)

        case .grpc:
            guard let data = request.grpcData else { break }
            scan(data.authority)
            scan(data.service)
            scan(data.method)
            scanEntries(data.metadata)
            scan(data.requestBodyJSON)
            scan(data.requestBodyHex)
        }

        return names
    }

    static func unresolvedVariables(
        in request: Request,
        environment: ApiEnvironment?
    ) -> [String] {
        let allVars = allVariableNames(in: request)
        guard !allVars.isEmpty else { return [] }

        let coveredKeys: Set<String>
        if let environment {
            coveredKeys = Set(
                environment.variables
                    .filter { $0.enabled && !$0.key.isEmpty }
                    .map(\.key)
            )
        } else {
            coveredKeys = []
        }

        return allVars.subtracting(coveredKeys).sorted()
    }
}
