//
//  CodeHighlighter.swift
//  Reqeast
//

import SwiftUI

enum CodeHighlighter {
    private static let maxHighlightSize = 100_000

    static func highlight(_ code: String, language: String, theme: CodeHighlightTheme) -> AttributedString {
        let monoFont = Font.system(.body, design: .monospaced)

        guard code.utf8.count <= maxHighlightSize else {
            var plain = AttributedString(code)
            plain.font = monoFont
            return plain
        }

        let spans = tokenize(code, language: language)
        return buildAttributedString(code, spans: spans, theme: theme, font: monoFont)
    }

    // MARK: - Tokenization

    private struct Span: Comparable {
        let range: Range<String.Index>
        let token: CodeToken

        static func < (lhs: Span, rhs: Span) -> Bool {
            lhs.range.lowerBound < rhs.range.lowerBound
        }
    }

    private static func tokenize(_ code: String, language: String) -> [Span] {
        var spans: [Span] = []

        spans.append(contentsOf: matchComments(code, language: language))
        spans.append(contentsOf: matchStrings(code, language: language))
        spans.append(contentsOf: matchNumbers(code))
        spans.append(contentsOf: matchKeywords(code, language: language))
        spans.append(contentsOf: matchTypes(code))

        spans.sort()
        return removeOverlaps(spans)
    }

    private static func removeOverlaps(_ sorted: [Span]) -> [Span] {
        var result: [Span] = []
        var end = "".startIndex

        for span in sorted {
            if span.range.lowerBound >= end {
                result.append(span)
                end = span.range.upperBound
            }
        }
        return result
    }

    // MARK: - Matchers

    private static func matchComments(_ code: String, language: String) -> [Span] {
        var patterns: [String] = []

        switch language {
        case "python", "bash":
            patterns.append("#[^\n]*")
        case "http":
            break
        default:
            patterns.append("//[^\n]*")
            patterns.append("/\\*[\\s\\S]*?\\*/")
        }

        return matchAll(code, patterns: patterns, token: .comment)
    }

    private static func matchStrings(_ code: String, language: String) -> [Span] {
        var patterns: [String] = []

        if language == "python" {
            patterns.append("\"\"\"[\\s\\S]*?\"\"\"")
            patterns.append("'''[\\s\\S]*?'''")
        }

        patterns.append("\"(?:[^\"\\\\]|\\\\.)*\"")
        patterns.append("'(?:[^'\\\\]|\\\\.)*'")

        if language == "go" {
            patterns.append("`[^`]*`")
        }

        return matchAll(code, patterns: patterns, token: .string)
    }

    private static func matchNumbers(_ code: String) -> [Span] {
        matchAll(code, patterns: ["(?<![a-zA-Z_])\\d+\\.?\\d*(?:[eE][+-]?\\d+)?"], token: .number)
    }

    private static func matchKeywords(_ code: String, language: String) -> [Span] {
        guard let wordSet = keywords[language] else { return [] }

        let pattern = "\\b(?:" + wordSet.sorted().joined(separator: "|") + ")\\b"
        return matchAll(code, patterns: [pattern], token: .keyword)
    }

    private static func matchTypes(_ code: String) -> [Span] {
        matchAll(code, patterns: ["\\b[A-Z][a-zA-Z0-9]+\\b"], token: .type)
    }

    private static func matchAll(_ code: String, patterns: [String], token: CodeToken) -> [Span] {
        var spans: [Span] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(code.startIndex..., in: code)
            for match in regex.matches(in: code, range: nsRange) {
                if let range = Range(match.range, in: code) {
                    spans.append(Span(range: range, token: token))
                }
            }
        }
        return spans
    }

    // MARK: - Build AttributedString

    private static func buildAttributedString(
        _ code: String,
        spans: [Span],
        theme: CodeHighlightTheme,
        font: Font
    ) -> AttributedString {
        var result = AttributedString()
        var cursor = code.startIndex

        for span in spans {
            if cursor < span.range.lowerBound {
                var plain = AttributedString(code[cursor..<span.range.lowerBound])
                plain.font = font
                plain.foregroundColor = theme.color(for: .plain)
                result.append(plain)
            }

            var segment = AttributedString(code[span.range])
            segment.font = font
            segment.foregroundColor = theme.color(for: span.token)
            result.append(segment)

            cursor = span.range.upperBound
        }

        if cursor < code.endIndex {
            var tail = AttributedString(code[cursor...])
            tail.font = font
            tail.foregroundColor = theme.color(for: .plain)
            result.append(tail)
        }

        return result
    }

    // MARK: - Keyword Tables

    private static let keywords: [String: Set<String>] = [
        "bash": [
            "curl", "echo", "if", "then", "fi", "for", "do", "done", "while",
            "case", "esac", "export", "local", "return", "exit", "set",
        ],
        "python": [
            "import", "from", "def", "class", "if", "elif", "else", "return",
            "for", "in", "while", "try", "except", "finally", "with", "as",
            "raise", "pass", "break", "continue", "and", "or", "not", "is",
            "None", "True", "False", "print", "async", "await", "yield",
        ],
        "javascript": [
            "const", "let", "var", "function", "async", "await", "return",
            "if", "else", "for", "while", "switch", "case", "break", "default",
            "try", "catch", "finally", "throw", "new", "class", "import",
            "export", "from", "of", "in", "typeof", "instanceof", "this",
            "true", "false", "null", "undefined", "console",
        ],
        "swift": [
            "import", "let", "var", "func", "struct", "class", "enum",
            "protocol", "extension", "if", "else", "guard", "return", "for",
            "in", "while", "switch", "case", "break", "default", "do", "try",
            "catch", "throw", "throws", "async", "await", "self", "Self",
            "true", "false", "nil", "private", "public", "static",
        ],
        "go": [
            "package", "import", "func", "if", "else", "return", "defer",
            "for", "range", "switch", "case", "break", "default", "var",
            "const", "type", "struct", "interface", "map", "make", "new",
            "go", "chan", "select", "nil", "true", "false", "err",
        ],
        "rust": [
            "use", "fn", "let", "mut", "async", "await", "pub", "impl",
            "struct", "enum", "trait", "if", "else", "match", "for", "in",
            "while", "loop", "return", "break", "continue", "self", "Self",
            "super", "crate", "mod", "where", "as", "ref", "move",
            "true", "false", "Some", "None", "Ok", "Err",
        ],
        "java": [
            "import", "public", "private", "protected", "class", "interface",
            "void", "new", "return", "if", "else", "for", "while", "switch",
            "case", "break", "default", "try", "catch", "finally", "throw",
            "throws", "static", "final", "this", "super", "extends",
            "implements", "true", "false", "null",
        ],
        "csharp": [
            "using", "var", "new", "public", "private", "protected", "class",
            "interface", "void", "string", "int", "bool", "async", "await",
            "return", "if", "else", "for", "foreach", "while", "switch",
            "case", "break", "default", "try", "catch", "finally", "throw",
            "static", "readonly", "namespace", "true", "false", "null",
            "this", "base",
        ],
        "http": [
            "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS",
            "HTTP", "HTTPS", "Content-Type", "Authorization", "Accept",
            "Host", "User-Agent", "Content-Length",
        ],
    ]
}
