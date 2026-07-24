//
//  HTMLHighlighter+Tokens.swift
//  Reqeast
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Token Types

enum HTMLToken {
    case tag
    case attribute
    case attributeValue
    case bracket
    case comment
    case text
}

// MARK: - Tokenization Helpers

extension HTMLHighlighter {
    static func isNameChar(_ c: Character) -> Bool {
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") ||
        (c >= "0" && c <= "9") || c == "-" || c == "_" || c == "." || c == ":"
    }

    static func matchesLiteral(chars: [Character], from: Int, count: Int, literal: String) -> Bool {
        let literalChars = Array(literal)
        guard from + literalChars.count <= count else { return false }
        for (offset, lc) in literalChars.enumerated() {
            if chars[from + offset] != lc { return false }
        }
        return true
    }
}

// MARK: - SwiftUI Theme

struct HTMLHighlightTheme {
    let defaultText: Color
    private let colors: [HTMLToken: Color]

    init(defaultText: Color, _ colors: [HTMLToken: Color]) {
        self.defaultText = defaultText
        self.colors = colors
    }

    func color(for token: HTMLToken) -> Color {
        colors[token] ?? defaultText
    }

    static let responseDarkSwiftUI = HTMLHighlightTheme(
        defaultText: Color(red: 0.92, green: 0.92, blue: 0.94),
        [
            .tag:            Color(red: 0.92, green: 0.46, blue: 0.55),
            .attribute:      Color(red: 0.55, green: 0.78, blue: 0.88),
            .attributeValue: Color(red: 0.45, green: 0.78, blue: 0.65),
            .bracket:        .secondary,
            .comment:        Color(red: 0.55, green: 0.55, blue: 0.58),
            .text:           Color(red: 0.92, green: 0.92, blue: 0.94),
        ]
    )

    static let responseLightSwiftUI = HTMLHighlightTheme(
        defaultText: Color(red: 0.10, green: 0.10, blue: 0.12),
        [
            .tag:            Color(red: 0.72, green: 0.18, blue: 0.30),
            .attribute:      Color(red: 0.38, green: 0.28, blue: 0.52),
            .attributeValue: Color(red: 0.18, green: 0.55, blue: 0.42),
            .bracket:        .secondary,
            .comment:        Color(red: 0.45, green: 0.45, blue: 0.48),
            .text:           Color(red: 0.10, green: 0.10, blue: 0.12),
        ]
    )
}

// MARK: - UIKit Theme (iOS)

#if os(iOS)
struct HTMLHighlightNSTheme {
    let defaultText: UIColor
    private let colors: [HTMLToken: UIColor]

    init(defaultText: UIColor, _ colors: [HTMLToken: UIColor]) {
        self.defaultText = defaultText
        self.colors = colors
    }

    func color(for token: HTMLToken) -> UIColor {
        colors[token] ?? defaultText
    }

    // MARK: - Response (read-only)

    static let responseDark = HTMLHighlightNSTheme(
        defaultText: UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1.0),
        [
            .tag:            UIColor(red: 0.92, green: 0.46, blue: 0.55, alpha: 1.0),
            .attribute:      UIColor(red: 0.55, green: 0.78, blue: 0.88, alpha: 1.0),
            .attributeValue: UIColor(red: 0.45, green: 0.78, blue: 0.65, alpha: 1.0),
            .bracket:        .secondaryLabel,
            .comment:        UIColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1.0),
            .text:           UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1.0),
        ]
    )

    static let responseLight = HTMLHighlightNSTheme(
        defaultText: UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
        [
            .tag:            UIColor(red: 0.72, green: 0.18, blue: 0.30, alpha: 1.0),
            .attribute:      UIColor(red: 0.38, green: 0.28, blue: 0.52, alpha: 1.0),
            .attributeValue: UIColor(red: 0.18, green: 0.55, blue: 0.42, alpha: 1.0),
            .bracket:        .secondaryLabel,
            .comment:        UIColor(red: 0.45, green: 0.45, blue: 0.48, alpha: 1.0),
            .text:           UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
        ]
    )
}
#endif
