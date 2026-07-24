//
//  WgetParser.swift
//  Reqeast
//

import Foundation

enum WgetParser {

    static func parse(_ tokens: [String]) throws -> ImportedRequestData {
        var data = ImportedRequestData()
        var index = 1 // skip "wget"

        while index < tokens.count {
            let token = tokens[index]

            if let (flag, value) = splitLongFlag(token) {
                applyFlag(flag: flag, value: value, data: &data)
            } else if token.hasPrefix("--") {
                let flag = token
                if flagNeedsValue(flag) {
                    index += 1
                    if index < tokens.count {
                        applyFlag(flag: flag, value: tokens[index], data: &data)
                    }
                } else {
                    applyFlag(flag: flag, value: nil, data: &data)
                }
            } else if token.hasPrefix("-") {
                // Short flags
                switch token {
                case "-O", "-o", "-P", "-t", "-T", "-w", "-Q", "-U":
                    index += 1 // skip value
                case "-q", "-v", "-S", "-c", "-N":
                    break // ignored
                default:
                    break
                }
            } else {
                if data.url.isEmpty {
                    data.url = token
                }
            }

            index += 1
        }

        if data.method == nil {
            data.method = data.body != nil ? "POST" : "GET"
        }

        guard !data.url.isEmpty else {
            throw ImportError.noUrlFound
        }

        return data
    }

    // MARK: - Private

    private static func splitLongFlag(_ token: String) -> (flag: String, value: String)? {
        guard token.hasPrefix("--") else { return nil }
        guard let eqIndex = token.firstIndex(of: "=") else { return nil }
        let flag = String(token[token.startIndex..<eqIndex])
        let value = String(token[token.index(after: eqIndex)...])
        return (flag: flag, value: value)
    }

    private static func flagNeedsValue(_ flag: String) -> Bool {
        switch flag {
        case "--method", "--header", "--body-data", "--body-file",
             "--http-user", "--http-password", "--post-data", "--post-file",
             "--user-agent", "--referer", "--output-document":
            return true
        default:
            return false
        }
    }

    private static func applyFlag(flag: String, value: String?, data: inout ImportedRequestData) {
        switch flag {
        case "--method":
            data.method = value?.uppercased()

        case "--header":
            if let value, let header = parseHeader(value) {
                data.headers.append(header)
            }

        case "--body-data", "--post-data":
            data.body = value

        case "--http-user":
            data.basicAuthUser = value

        case "--http-password":
            data.basicAuthPassword = value

        case "--no-check-certificate":
            data.insecure = true

        default:
            break
        }
    }

    private static func parseHeader(_ raw: String) -> (name: String, value: String)? {
        guard let colonIndex = raw.firstIndex(of: ":") else { return nil }
        let name = String(raw[raw.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let valueStart = raw.index(after: colonIndex)
        let value = String(raw[valueStart...]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return (name: name, value: value)
    }
}
