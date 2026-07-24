//
//  ImportRequestService.swift
//  Reqeast
//

import Foundation

enum ImportRequestService {

    static func canImport(into request: Request) -> Bool {
        request.type == .http
    }

    static func detectFormat(_ input: String) -> ImportFormat? {
        let firstToken = extractFirstToken(input)
        switch firstToken {
        case "curl", "curlie":                        return .curl
        case "wget", "wget2", "aria2c":               return .wget
        case "http", "https", "xh", "xhs", "httpie":  return .httpie
        default:                                       return nil
        }
    }

    static func parse(_ input: String) throws -> ParsedImportResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyInput }

        let format = detectFormat(trimmed)

        switch format {
        case .curl:
            return try parseCurl(trimmed)
        case .wget:
            let data = try parseWithTokenizer(trimmed, parser: WgetParser.parse)
            return ParsedImportResult(data: data)
        case .httpie:
            let data = try parseWithTokenizer(trimmed, parser: HttpieParser.parse)
            return ParsedImportResult(data: data)
        case .appleIntelligence:
            let command = extractFirstToken(trimmed)
            throw ImportError.unknownFormat(command)
        case nil:
            let command = extractFirstToken(trimmed)
            throw ImportError.unknownFormat(command)
        }
    }

    // MARK: - Private

    private static func parseCurl(_ input: String) throws -> ParsedImportResult {
        let json = try CurlConverterBridge.parse(input)
        return CurlConverterMapper.map(json)
    }

    private static func parseWithTokenizer(
        _ input: String,
        parser: ([String]) throws -> ImportedRequestData
    ) throws -> ImportedRequestData {
        var tokens = ShellTokenizer.tokenize(input)
        guard !tokens.isEmpty else { throw ImportError.emptyInput }

        while let first = tokens.first, isPromptToken(first) {
            tokens.removeFirst()
        }
        guard !tokens.isEmpty else { throw ImportError.emptyInput }

        return try parser(tokens)
    }

    private static func isPromptToken(_ token: String) -> Bool {
        token.allSatisfy { $0 == "$" || $0 == "%" || $0 == ">" }
    }

    private static func extractFirstToken(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard let first = words.first else { return "" }
        let stripped = stripPrompt(String(first))
        if stripped.isEmpty, words.count > 1 {
            return String(words[1])
        }
        return stripped
    }

    private static func stripPrompt(_ token: String) -> String {
        var result = token
        while result.hasPrefix("$") || result.hasPrefix("%") || result.hasPrefix(">") {
            result = String(result.dropFirst())
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
