//
//  JqFilterService.swift
//  Reqeast
//

import Foundation

enum JqFilterResult {
    case success(String)
    case failure(String)
}

enum JqFilterService {
    /// Full filter pipeline: UTF-8 decode, optional deep parse, jq evaluation, optional
    /// unquoting. `@concurrent` because every step is CPU-bound (the jq call is a synchronous
    /// UniFFI function) and multi-MB bodies would freeze the caller's actor. Structured, so
    /// the caller's priority carries over, unlike the previous `Task.detached` hop.
    /// Returns nil when the body is not valid UTF-8.
    @concurrent
    static func filteredOutput(
        body: Data,
        expression: String,
        unquote: Bool
    ) async -> (result: JqFilterResult, display: String?)? {
        guard let rawJson = String(data: body, encoding: .utf8) else { return nil }
        let json = unquote ? deepParseJsonStrings(rawJson) : rawJson
        let result = evaluate(expression: expression, json: json)
        guard case .success(let text) = result else { return (result, nil) }
        return (result, unquote ? unquoteStrings(text) : text)
    }

    static func evaluate(expression: String, json: String) -> JqFilterResult {
        do {
            let result = try jqFilter(jsonInput: json, filterExpression: expression)
            return .success(result)
        } catch {
            if case let .InvalidConfig(message) = error as? ReqeastError {
                return .failure(message)
            }
            return .failure(error.localizedDescription)
        }
    }

    static func unquoteStrings(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("\""),
                      let data = trimmed.data(using: .utf8),
                      let decoded = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
                else { return String(line) }
                return decoded
            }
            .joined(separator: "\n")
    }

    /// Recursively parses string values that contain valid JSON into actual JSON objects.
    /// This allows jq filters like `.data.content` to work when `.data` is a JSON-encoded string.
    static func deepParseJsonStrings(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
            return json
        }
        let parsed = recursivelyParseStrings(object)
        guard let resultData = try? JSONSerialization.data(withJSONObject: parsed),
              let result = String(data: resultData, encoding: .utf8) else {
            return json
        }
        return result
    }

    private static func recursivelyParseStrings(_ value: Any) -> Any {
        // Only unwrap string values that parse to a dict or array. Rejecting scalar parses
        // prevents `"1.0"` from silently becoming the number 1.0 (breaking jq equality like
        // `.version == "1.0"`), and `"true"` becoming bool, `"null"` becoming NSNull.
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
           (parsed is NSDictionary || parsed is NSArray) {
            return recursivelyParseStrings(parsed)
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { recursivelyParseStrings($0) }
        }
        if let array = value as? [Any] {
            return array.map { recursivelyParseStrings($0) }
        }
        return value
    }
}
