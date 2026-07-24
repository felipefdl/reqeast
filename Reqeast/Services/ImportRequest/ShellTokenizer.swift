//
//  ShellTokenizer.swift
//  Reqeast
//

import Foundation

enum ShellTokenizer {

    static func tokenize(_ input: String) -> [String] {
        let preprocessed = input
            .replacingOccurrences(of: "\\\n", with: "")
            .replacingOccurrences(of: "\\\r\n", with: "")

        var tokens: [String] = []
        var current = ""
        var state: State = .normal
        var iterator = preprocessed.makeIterator()

        while let char = iterator.next() {
            switch state {
            case .normal:
                switch char {
                case " ", "\t", "\n", "\r":
                    if !current.isEmpty {
                        tokens.append(current)
                        current = ""
                    }
                case "'":
                    state = .inSingleQuote
                case "\"":
                    state = .inDoubleQuote
                case "\\":
                    if let next = iterator.next() {
                        current.append(next)
                    }
                case "$":
                    if let next = iterator.next() {
                        if next == "'" {
                            state = .inAnsiCQuote
                        } else {
                            current.append(char)
                            current.append(next)
                        }
                    } else {
                        current.append(char)
                    }
                default:
                    current.append(char)
                }

            case .inSingleQuote:
                if char == "'" {
                    state = .normal
                } else {
                    current.append(char)
                }

            case .inDoubleQuote:
                if char == "\"" {
                    state = .normal
                } else if char == "\\" {
                    if let next = iterator.next() {
                        if next == "\"" || next == "\\" || next == "$" || next == "`" {
                            current.append(next)
                        } else {
                            current.append(char)
                            current.append(next)
                        }
                    }
                } else {
                    current.append(char)
                }

            case .inAnsiCQuote:
                if char == "'" {
                    state = .normal
                } else if char == "\\" {
                    if let next = iterator.next() {
                        current.append(ansiCEscape(next))
                    }
                } else {
                    current.append(char)
                }
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    // MARK: - Private

    private enum State {
        case normal
        case inSingleQuote
        case inDoubleQuote
        case inAnsiCQuote
    }

    private static func ansiCEscape(_ char: Character) -> Character {
        switch char {
        case "n":  return "\n"
        case "t":  return "\t"
        case "r":  return "\r"
        case "\\": return "\\"
        case "'":  return "'"
        case "\"": return "\""
        case "a":  return "\u{07}"
        case "b":  return "\u{08}"
        case "f":  return "\u{0C}"
        case "v":  return "\u{0B}"
        default:   return char
        }
    }
}
