//
//  HTMLHighlighter.swift
//  Reqeast
//

import SwiftUI

enum HTMLHighlighter {
    private static let maxHighlightSize = 100_000

    // MARK: - AttributedString Rendering

    static func highlight(_ htmlString: String, theme: HTMLHighlightTheme) -> AttributedString {
        let monoFont = Font.system(.body, design: .monospaced)

        guard htmlString.utf8.count <= maxHighlightSize else {
            var str = AttributedString(htmlString)
            str.font = monoFont
            str.foregroundColor = theme.defaultText
            return str
        }

        var result = AttributedString()
        let chars = Array(htmlString)
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

            if ch == "<" {
                // Comment: <!-- ... -->
                if matchesLiteral(chars: chars, from: i, count: count, literal: "<!--") {
                    let start = i
                    i += 4
                    while i < count {
                        if matchesLiteral(chars: chars, from: i, count: count, literal: "-->") {
                            i += 3
                            break
                        }
                        i += 1
                    }
                    append(String(chars[start..<i]), color: theme.color(for: .comment))
                    continue
                }

                // CDATA: <![CDATA[ ... ]]>
                if matchesLiteral(chars: chars, from: i, count: count, literal: "<![CDATA[") {
                    let start = i
                    i += 9
                    while i < count {
                        if matchesLiteral(chars: chars, from: i, count: count, literal: "]]>") {
                            i += 3
                            break
                        }
                        i += 1
                    }
                    append(String(chars[start..<i]), color: theme.color(for: .comment))
                    continue
                }

                // DOCTYPE: <!DOCTYPE ...>
                if matchesLiteral(chars: chars, from: i, count: count, literal: "<!") {
                    let start = i
                    while i < count && chars[i] != ">" { i += 1 }
                    if i < count { i += 1 }
                    append(String(chars[start..<i]), color: theme.color(for: .comment))
                    continue
                }

                // Processing instruction: <?xml ... ?>
                if matchesLiteral(chars: chars, from: i, count: count, literal: "<?") {
                    let start = i
                    i += 2
                    while i < count {
                        if matchesLiteral(chars: chars, from: i, count: count, literal: "?>") {
                            i += 2
                            break
                        }
                        i += 1
                    }
                    append(String(chars[start..<i]), color: theme.color(for: .comment))
                    continue
                }

                // Opening bracket
                append("<", color: theme.color(for: .bracket))
                i += 1

                // Closing tag slash
                if i < count && chars[i] == "/" {
                    append("/", color: theme.color(for: .bracket))
                    i += 1
                }

                // Tag name
                let nameStart = i
                while i < count && isNameChar(chars[i]) { i += 1 }
                if i > nameStart {
                    append(String(chars[nameStart..<i]), color: theme.color(for: .tag))
                }

                // Attributes and closing
                while i < count && chars[i] != ">" {
                    let ac = chars[i]

                    if ac == " " || ac == "\t" || ac == "\n" || ac == "\r" {
                        append(String(ac))
                        i += 1
                        continue
                    }

                    if ac == "/" {
                        append("/", color: theme.color(for: .bracket))
                        i += 1
                        continue
                    }

                    if ac == "=" {
                        append("=", color: theme.color(for: .bracket))
                        i += 1

                        // Skip whitespace after =
                        while i < count && (chars[i] == " " || chars[i] == "\t") {
                            append(String(chars[i]))
                            i += 1
                        }

                        // Attribute value
                        if i < count && (chars[i] == "\"" || chars[i] == "'") {
                            let quote = chars[i]
                            let valStart = i
                            i += 1
                            while i < count && chars[i] != quote { i += 1 }
                            if i < count { i += 1 }
                            append(String(chars[valStart..<i]), color: theme.color(for: .attributeValue))
                        } else {
                            // Unquoted value
                            let valStart = i
                            while i < count && chars[i] != " " && chars[i] != ">" && chars[i] != "/" {
                                i += 1
                            }
                            if i > valStart {
                                append(String(chars[valStart..<i]), color: theme.color(for: .attributeValue))
                            }
                        }
                        continue
                    }

                    // Attribute name
                    if isNameChar(ac) {
                        let attrStart = i
                        while i < count && isNameChar(chars[i]) { i += 1 }
                        append(String(chars[attrStart..<i]), color: theme.color(for: .attribute))
                        continue
                    }

                    append(String(ac))
                    i += 1
                }

                // Closing bracket
                if i < count && chars[i] == ">" {
                    append(">", color: theme.color(for: .bracket))
                    i += 1
                }
            } else {
                // Text content between tags
                let textStart = i
                while i < count && chars[i] != "<" { i += 1 }
                append(String(chars[textStart..<i]), color: theme.color(for: .text))
            }
        }

        return result
    }

    // MARK: - NSAttributedString Rendering (iOS)

    #if os(iOS)
    static func highlightNS(_ htmlString: String, theme: HTMLHighlightNSTheme) -> NSAttributedString {
        let monoFont = UIFont.monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)

        guard htmlString.utf8.count <= maxHighlightSize else {
            return NSAttributedString(
                string: htmlString,
                attributes: [.font: monoFont, .foregroundColor: theme.defaultText]
            )
        }

        let result = NSMutableAttributedString()
        let chars = Array(htmlString)
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

            if ch == "<" {
                // Comment: <!-- ... -->
                if matchesLiteral(chars: chars, from: i, count: count, literal: "<!--") {
                    let start = i
                    i += 4
                    while i < count {
                        if matchesLiteral(chars: chars, from: i, count: count, literal: "-->") {
                            i += 3
                            break
                        }
                        i += 1
                    }
                    append(String(chars[start..<i]), color: theme.color(for: .comment))
                    continue
                }

                // CDATA: <![CDATA[ ... ]]>
                // Styled as .comment since we have no dedicated CDATA token
                if matchesLiteral(chars: chars, from: i, count: count, literal: "<![CDATA[") {
                    let start = i
                    i += 9
                    while i < count {
                        if matchesLiteral(chars: chars, from: i, count: count, literal: "]]>") {
                            i += 3
                            break
                        }
                        i += 1
                    }
                    append(String(chars[start..<i]), color: theme.color(for: .comment))
                    continue
                }

                // DOCTYPE: <!DOCTYPE ...>
                if matchesLiteral(chars: chars, from: i, count: count, literal: "<!") {
                    let start = i
                    while i < count && chars[i] != ">" { i += 1 }
                    if i < count { i += 1 }
                    append(String(chars[start..<i]), color: theme.color(for: .comment))
                    continue
                }

                // Processing instruction: <?xml ... ?>
                if matchesLiteral(chars: chars, from: i, count: count, literal: "<?") {
                    let start = i
                    i += 2
                    while i < count {
                        if matchesLiteral(chars: chars, from: i, count: count, literal: "?>") {
                            i += 2
                            break
                        }
                        i += 1
                    }
                    append(String(chars[start..<i]), color: theme.color(for: .comment))
                    continue
                }

                // Opening bracket
                append("<", color: theme.color(for: .bracket))
                i += 1

                // Closing tag slash
                if i < count && chars[i] == "/" {
                    append("/", color: theme.color(for: .bracket))
                    i += 1
                }

                // Tag name
                let nameStart = i
                while i < count && isNameChar(chars[i]) { i += 1 }
                if i > nameStart {
                    append(String(chars[nameStart..<i]), color: theme.color(for: .tag))
                }

                // Attributes and closing
                while i < count && chars[i] != ">" {
                    let ac = chars[i]

                    if ac == " " || ac == "\t" || ac == "\n" || ac == "\r" {
                        append(String(ac))
                        i += 1
                        continue
                    }

                    if ac == "/" {
                        append("/", color: theme.color(for: .bracket))
                        i += 1
                        continue
                    }

                    if ac == "=" {
                        append("=", color: theme.color(for: .bracket))
                        i += 1

                        // Skip whitespace after =
                        while i < count && (chars[i] == " " || chars[i] == "\t") {
                            append(String(chars[i]))
                            i += 1
                        }

                        // Attribute value
                        if i < count && (chars[i] == "\"" || chars[i] == "'") {
                            let quote = chars[i]
                            let valStart = i
                            i += 1
                            while i < count && chars[i] != quote { i += 1 }
                            if i < count { i += 1 }
                            append(String(chars[valStart..<i]), color: theme.color(for: .attributeValue))
                        } else {
                            // Unquoted value
                            let valStart = i
                            while i < count && chars[i] != " " && chars[i] != ">" && chars[i] != "/" {
                                i += 1
                            }
                            if i > valStart {
                                append(String(chars[valStart..<i]), color: theme.color(for: .attributeValue))
                            }
                        }
                        continue
                    }

                    // Attribute name
                    if isNameChar(ac) {
                        let attrStart = i
                        while i < count && isNameChar(chars[i]) { i += 1 }
                        append(String(chars[attrStart..<i]), color: theme.color(for: .attribute))
                        continue
                    }

                    append(String(ac))
                    i += 1
                }

                // Closing bracket
                if i < count && chars[i] == ">" {
                    append(">", color: theme.color(for: .bracket))
                    i += 1
                }
            } else {
                // Text content between tags
                let textStart = i
                while i < count && chars[i] != "<" { i += 1 }
                append(String(chars[textStart..<i]), color: theme.color(for: .text))
            }
        }

        return result
    }
    #endif
}
