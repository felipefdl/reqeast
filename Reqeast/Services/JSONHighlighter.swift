//
//  JSONHighlighter.swift
//  Reqeast
//

import SwiftUI

enum JSONToken {
    case key
    case stringValue
    case numberValue
    case booleanValue
    case nullValue
    case punctuation
}

enum JSONHighlighter {
    private static let maxHighlightSize = 100_000

    // MARK: - Helpers

    private static func isKey(chars: [Character], from index: Int, count: Int) -> Bool {
        var j = index
        while j < count {
            let c = chars[j]
            if c == ":" { return true }
            if c == " " || c == "\t" || c == "\n" || c == "\r" {
                j += 1
                continue
            }
            return false
        }
        return false
    }

    private static func consumeNumber(chars: [Character], from start: Int, count: Int) -> Int {
        var i = start
        if i < count && chars[i] == "-" { i += 1 }
        while i < count && chars[i] >= "0" && chars[i] <= "9" { i += 1 }
        if i < count && chars[i] == "." {
            i += 1
            while i < count && chars[i] >= "0" && chars[i] <= "9" { i += 1 }
        }
        if i < count && (chars[i] == "e" || chars[i] == "E") {
            i += 1
            if i < count && (chars[i] == "+" || chars[i] == "-") { i += 1 }
            while i < count && chars[i] >= "0" && chars[i] <= "9" { i += 1 }
        }
        return i
    }

    private static func matchesLiteral(chars: [Character], from: Int, count: Int, literal: String) -> Bool {
        let literalChars = Array(literal)
        guard from + literalChars.count <= count else { return false }
        for (offset, lc) in literalChars.enumerated() {
            if chars[from + offset] != lc { return false }
        }
        return true
    }

    // MARK: - SwiftUI AttributedString

    static func highlight(_ jsonString: String, theme: JSONHighlightTheme) -> AttributedString {
        let monoFont = Font.system(.body, design: .monospaced)

        guard jsonString.utf8.count <= maxHighlightSize else {
            var fallback = AttributedString(jsonString)
            fallback.font = monoFont
            fallback.foregroundColor = theme.defaultText
            return fallback
        }

        var result = AttributedString()
        let chars = Array(jsonString)
        let count = chars.count
        var i = 0

        func append(_ text: String, color: Color? = nil) {
            var str = AttributedString(text)
            str.font = monoFont
            str.foregroundColor = color ?? theme.defaultText
            result.append(str)
        }

        while i < count {
            let ch = chars[i]

            switch ch {
            case "\"":
                let stringStart = i
                i += 1
                while i < count && chars[i] != "\"" {
                    if chars[i] == "\\" { i += 1 }
                    i += 1
                }
                if i < count { i += 1 }
                let content = String(chars[stringStart..<i])
                let token: JSONToken = isKey(chars: chars, from: i, count: count) ? .key : .stringValue
                append(content, color: theme.color(for: token))

            case "-", "0"..."9":
                let numStart = i
                i = consumeNumber(chars: chars, from: i, count: count)
                append(String(chars[numStart..<i]), color: theme.color(for: .numberValue))

            case "t", "f":
                if matchesLiteral(chars: chars, from: i, count: count, literal: "true") {
                    append("true", color: theme.color(for: .booleanValue))
                    i += 4
                } else if matchesLiteral(chars: chars, from: i, count: count, literal: "false") {
                    append("false", color: theme.color(for: .booleanValue))
                    i += 5
                } else {
                    append(String(ch))
                    i += 1
                }

            case "n":
                if matchesLiteral(chars: chars, from: i, count: count, literal: "null") {
                    append("null", color: theme.color(for: .nullValue))
                    i += 4
                } else {
                    append(String(ch))
                    i += 1
                }

            case "{", "}", "[", "]", ",", ":":
                append(String(ch), color: theme.color(for: .punctuation))
                i += 1

            default:
                append(String(ch))
                i += 1
            }
        }

        return result
    }

    // MARK: - UIKit NSAttributedString (iOS)

    #if os(iOS)
    static func highlightNS(_ jsonString: String, theme: JSONHighlightNSTheme) -> NSAttributedString {
        let monoFont = UIFont.monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)

        guard jsonString.utf8.count <= maxHighlightSize else {
            return NSAttributedString(
                string: jsonString,
                attributes: [.font: monoFont, .foregroundColor: theme.defaultText]
            )
        }

        let result = NSMutableAttributedString()
        let chars = Array(jsonString)
        let count = chars.count
        var i = 0

        func append(_ text: String, color: UIColor? = nil) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: monoFont,
                .foregroundColor: color ?? theme.defaultText,
            ]
            result.append(NSAttributedString(string: text, attributes: attrs))
        }

        while i < count {
            let ch = chars[i]

            switch ch {
            case "\"":
                let stringStart = i
                i += 1
                while i < count && chars[i] != "\"" {
                    if chars[i] == "\\" { i += 1 }
                    i += 1
                }
                if i < count { i += 1 }
                let content = String(chars[stringStart..<i])
                let token: JSONToken = isKey(chars: chars, from: i, count: count) ? .key : .stringValue
                append(content, color: theme.color(for: token))

            case "-", "0"..."9":
                let numStart = i
                i = consumeNumber(chars: chars, from: i, count: count)
                append(String(chars[numStart..<i]), color: theme.color(for: .numberValue))

            case "t", "f":
                if matchesLiteral(chars: chars, from: i, count: count, literal: "true") {
                    append("true", color: theme.color(for: .booleanValue))
                    i += 4
                } else if matchesLiteral(chars: chars, from: i, count: count, literal: "false") {
                    append("false", color: theme.color(for: .booleanValue))
                    i += 5
                } else {
                    append(String(ch))
                    i += 1
                }

            case "n":
                if matchesLiteral(chars: chars, from: i, count: count, literal: "null") {
                    append("null", color: theme.color(for: .nullValue))
                    i += 4
                } else {
                    append(String(ch))
                    i += 1
                }

            case "{", "}", "[", "]", ",", ":":
                append(String(ch), color: theme.color(for: .punctuation))
                i += 1

            default:
                append(String(ch))
                i += 1
            }
        }

        return result
    }
    #endif
}

// MARK: - UIKit Theme (iOS)

#if os(iOS)
struct JSONHighlightNSTheme {
    let defaultText: UIColor
    private let colors: [JSONToken: UIColor]

    init(defaultText: UIColor, _ colors: [JSONToken: UIColor]) {
        self.defaultText = defaultText
        self.colors = colors
    }

    func color(for token: JSONToken) -> UIColor {
        colors[token] ?? defaultText
    }

    // MARK: - Request (editable)

    static let dark = JSONHighlightNSTheme(
        defaultText: UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1.0),
        [
            .key:          UIColor(red: 0.70, green: 0.55, blue: 0.92, alpha: 1.0),
            .stringValue:  UIColor(red: 0.99, green: 0.42, blue: 0.35, alpha: 1.0),
            .numberValue:  UIColor(red: 0.82, green: 0.75, blue: 0.50, alpha: 1.0),
            .booleanValue: UIColor(red: 0.99, green: 0.42, blue: 0.62, alpha: 1.0),
            .nullValue:    UIColor(red: 0.99, green: 0.42, blue: 0.62, alpha: 1.0),
            .punctuation:  .secondaryLabel,
        ]
    )

    static let light = JSONHighlightNSTheme(
        defaultText: UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
        [
            .key:          UIColor(red: 0.33, green: 0.22, blue: 0.62, alpha: 1.0),
            .stringValue:  UIColor(red: 0.77, green: 0.10, blue: 0.09, alpha: 1.0),
            .numberValue:  UIColor(red: 0.11, green: 0.00, blue: 0.81, alpha: 1.0),
            .booleanValue: UIColor(red: 0.72, green: 0.21, blue: 0.62, alpha: 1.0),
            .nullValue:    UIColor(red: 0.72, green: 0.21, blue: 0.62, alpha: 1.0),
            .punctuation:  .secondaryLabel,
        ]
    )

    // MARK: - Response (read-only)

    static let responseDark = JSONHighlightNSTheme(
        defaultText: UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1.0),
        [
            .key:          UIColor(red: 0.55, green: 0.78, blue: 0.88, alpha: 1.0),
            .stringValue:  UIColor(red: 0.45, green: 0.78, blue: 0.65, alpha: 1.0),
            .numberValue:  UIColor(red: 0.78, green: 0.72, blue: 0.50, alpha: 1.0),
            .booleanValue: UIColor(red: 0.90, green: 0.45, blue: 0.65, alpha: 1.0),
            .nullValue:    UIColor(red: 0.90, green: 0.45, blue: 0.65, alpha: 1.0),
            .punctuation:  .secondaryLabel,
        ]
    )

    static let responseLight = JSONHighlightNSTheme(
        defaultText: UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
        [
            .key:          UIColor(red: 0.38, green: 0.28, blue: 0.52, alpha: 1.0),
            .stringValue:  UIColor(red: 0.18, green: 0.55, blue: 0.42, alpha: 1.0),
            .numberValue:  UIColor(red: 0.13, green: 0.05, blue: 0.72, alpha: 1.0),
            .booleanValue: UIColor(red: 0.65, green: 0.22, blue: 0.55, alpha: 1.0),
            .nullValue:    UIColor(red: 0.65, green: 0.22, blue: 0.55, alpha: 1.0),
            .punctuation:  .secondaryLabel,
        ]
    )
}
#endif

// MARK: - SwiftUI Theme

struct JSONHighlightTheme {
    let defaultText: Color
    private let colors: [JSONToken: Color]

    init(defaultText: Color, _ colors: [JSONToken: Color]) {
        self.defaultText = defaultText
        self.colors = colors
    }

    func color(for token: JSONToken) -> Color {
        colors[token] ?? defaultText
    }

    // MARK: - Request (editable)

    static let darkSwiftUI = JSONHighlightTheme(
        defaultText: Color(red: 0.92, green: 0.92, blue: 0.94),
        [
            .key:          Color(red: 0.70, green: 0.55, blue: 0.92),
            .stringValue:  Color(red: 0.99, green: 0.42, blue: 0.35),
            .numberValue:  Color(red: 0.82, green: 0.75, blue: 0.50),
            .booleanValue: Color(red: 0.99, green: 0.42, blue: 0.62),
            .nullValue:    Color(red: 0.99, green: 0.42, blue: 0.62),
            .punctuation:  .secondary,
        ]
    )

    static let lightSwiftUI = JSONHighlightTheme(
        defaultText: Color(red: 0.10, green: 0.10, blue: 0.12),
        [
            .key:          Color(red: 0.33, green: 0.22, blue: 0.62),
            .stringValue:  Color(red: 0.77, green: 0.10, blue: 0.09),
            .numberValue:  Color(red: 0.11, green: 0.00, blue: 0.81),
            .booleanValue: Color(red: 0.72, green: 0.21, blue: 0.62),
            .nullValue:    Color(red: 0.72, green: 0.21, blue: 0.62),
            .punctuation:  .secondary,
        ]
    )

    // MARK: - Response (read-only)

    static let responseDarkSwiftUI = JSONHighlightTheme(
        defaultText: Color(red: 0.92, green: 0.92, blue: 0.94),
        [
            .key:          Color(red: 0.55, green: 0.78, blue: 0.88),
            .stringValue:  Color(red: 0.45, green: 0.78, blue: 0.65),
            .numberValue:  Color(red: 0.78, green: 0.72, blue: 0.50),
            .booleanValue: Color(red: 0.90, green: 0.45, blue: 0.65),
            .nullValue:    Color(red: 0.90, green: 0.45, blue: 0.65),
            .punctuation:  .secondary,
        ]
    )

    static let responseLightSwiftUI = JSONHighlightTheme(
        defaultText: Color(red: 0.10, green: 0.10, blue: 0.12),
        [
            .key:          Color(red: 0.38, green: 0.28, blue: 0.52),
            .stringValue:  Color(red: 0.18, green: 0.55, blue: 0.42),
            .numberValue:  Color(red: 0.13, green: 0.05, blue: 0.72),
            .booleanValue: Color(red: 0.65, green: 0.22, blue: 0.55),
            .nullValue:    Color(red: 0.65, green: 0.22, blue: 0.55),
            .punctuation:  .secondary,
        ]
    )
}
