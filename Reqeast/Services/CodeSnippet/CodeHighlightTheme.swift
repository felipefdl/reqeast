//
//  CodeHighlightTheme.swift
//  Reqeast
//

import SwiftUI

enum CodeToken {
    case keyword
    case string
    case number
    case comment
    case type
    case plain
}

struct CodeHighlightTheme {
    let colorScheme: ColorScheme

    func color(for token: CodeToken) -> Color {
        switch (token, colorScheme) {
        case (.keyword, .dark):  return Color(red: 0.99, green: 0.42, blue: 0.62)
        case (.keyword, _):      return Color(red: 0.72, green: 0.21, blue: 0.62)
        case (.string, .dark):   return Color(red: 0.99, green: 0.42, blue: 0.35)
        case (.string, _):       return Color(red: 0.77, green: 0.10, blue: 0.09)
        case (.number, .dark):   return Color(red: 0.82, green: 0.75, blue: 0.50)
        case (.number, _):       return Color(red: 0.11, green: 0.00, blue: 0.81)
        case (.comment, .dark):  return Color(red: 0.42, green: 0.47, blue: 0.53)
        case (.comment, _):      return Color(red: 0.38, green: 0.45, blue: 0.42)
        case (.type, .dark):     return Color(red: 0.39, green: 0.83, blue: 0.98)
        case (.type, _):         return Color(red: 0.11, green: 0.43, blue: 0.55)
        case (.plain, _):        return .primary
        }
    }
}
