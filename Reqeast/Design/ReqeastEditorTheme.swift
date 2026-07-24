//
//  ReqeastEditorTheme.swift
//  Reqeast
//

#if os(macOS)
import AppKit
import CodeEditSourceEditor

enum ReqeastEditorTheme {

    // MARK: - Request (editable)

    static let dark = EditorTheme(
        text: .init(color: NSColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1.0)),
        insertionPoint: NSColor.controlAccentColor,
        invisibles: .init(color: NSColor(red: 0.33, green: 0.37, blue: 0.43, alpha: 1.0)),
        background: NSColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1.0),
        lineHighlight: NSColor.white.withAlphaComponent(0.05),
        selection: NSColor.white.withAlphaComponent(0.15),
        keywords: .init(color: NSColor(red: 0.99, green: 0.42, blue: 0.62, alpha: 1.0), bold: true),
        commands: .init(color: NSColor(red: 0.51, green: 0.75, blue: 0.82, alpha: 1.0)),
        types: .init(color: NSColor(red: 0.42, green: 0.87, blue: 1.0, alpha: 1.0)),
        attributes: .init(color: NSColor(red: 0.80, green: 0.60, blue: 0.41, alpha: 1.0)),
        variables: .init(color: NSColor(red: 0.51, green: 0.75, blue: 0.82, alpha: 1.0)),
        values: .init(color: NSColor(red: 0.70, green: 0.51, blue: 0.92, alpha: 1.0)),
        numbers: .init(color: NSColor(red: 0.82, green: 0.75, blue: 0.50, alpha: 1.0)),
        strings: .init(color: NSColor(red: 0.99, green: 0.42, blue: 0.35, alpha: 1.0)),
        characters: .init(color: NSColor(red: 0.82, green: 0.75, blue: 0.50, alpha: 1.0)),
        comments: .init(color: NSColor(red: 0.50, green: 0.55, blue: 0.60, alpha: 1.0))
    )

    static let light = EditorTheme(
        text: .init(color: NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)),
        insertionPoint: NSColor.controlAccentColor,
        invisibles: .init(color: NSColor(red: 0.75, green: 0.75, blue: 0.78, alpha: 1.0)),
        background: NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0),
        lineHighlight: NSColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1.0),
        selection: NSColor(red: 0.70, green: 0.80, blue: 0.95, alpha: 1.0),
        keywords: .init(color: NSColor(red: 0.72, green: 0.21, blue: 0.62, alpha: 1.0), bold: true),
        commands: .init(color: NSColor(red: 0.44, green: 0.26, blue: 0.58, alpha: 1.0)),
        types: .init(color: NSColor(red: 0.11, green: 0.00, blue: 0.81, alpha: 1.0)),
        attributes: .init(color: NSColor(red: 0.58, green: 0.38, blue: 0.21, alpha: 1.0)),
        variables: .init(color: NSColor(red: 0.44, green: 0.26, blue: 0.58, alpha: 1.0)),
        values: .init(color: NSColor(red: 0.44, green: 0.26, blue: 0.58, alpha: 1.0)),
        numbers: .init(color: NSColor(red: 0.11, green: 0.00, blue: 0.81, alpha: 1.0)),
        strings: .init(color: NSColor(red: 0.77, green: 0.10, blue: 0.09, alpha: 1.0)),
        characters: .init(color: NSColor(red: 0.11, green: 0.00, blue: 0.81, alpha: 1.0)),
        comments: .init(color: NSColor(red: 0.45, green: 0.50, blue: 0.55, alpha: 1.0))
    )

    // MARK: - Response (read-only)

    static let responseDark = EditorTheme(
        text: .init(color: NSColor(red: 0.85, green: 0.88, blue: 0.92, alpha: 1.0)),
        insertionPoint: NSColor.controlAccentColor,
        invisibles: .init(color: NSColor(red: 0.30, green: 0.33, blue: 0.38, alpha: 1.0)),
        background: NSColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1.0),
        lineHighlight: NSColor.white.withAlphaComponent(0.03),
        selection: NSColor.white.withAlphaComponent(0.12),
        keywords: .init(color: NSColor(red: 0.90, green: 0.45, blue: 0.65, alpha: 1.0)),
        commands: .init(color: NSColor(red: 0.55, green: 0.78, blue: 0.88, alpha: 1.0)),
        types: .init(color: NSColor(red: 0.50, green: 0.82, blue: 0.95, alpha: 1.0)),
        attributes: .init(color: NSColor(red: 0.75, green: 0.58, blue: 0.42, alpha: 1.0)),
        variables: .init(color: NSColor(red: 0.55, green: 0.78, blue: 0.88, alpha: 1.0)),
        values: .init(color: NSColor(red: 0.65, green: 0.52, blue: 0.88, alpha: 1.0)),
        numbers: .init(color: NSColor(red: 0.78, green: 0.72, blue: 0.50, alpha: 1.0)),
        strings: .init(color: NSColor(red: 0.45, green: 0.78, blue: 0.65, alpha: 1.0)),
        characters: .init(color: NSColor(red: 0.78, green: 0.72, blue: 0.50, alpha: 1.0)),
        comments: .init(color: NSColor(red: 0.45, green: 0.50, blue: 0.55, alpha: 1.0))
    )

    static let responseLight = EditorTheme(
        text: .init(color: NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)),
        insertionPoint: NSColor.controlAccentColor,
        invisibles: .init(color: NSColor(red: 0.72, green: 0.72, blue: 0.75, alpha: 1.0)),
        background: NSColor(red: 0.94, green: 0.95, blue: 0.96, alpha: 1.0),
        lineHighlight: NSColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1.0),
        selection: NSColor(red: 0.75, green: 0.82, blue: 0.90, alpha: 1.0),
        keywords: .init(color: NSColor(red: 0.65, green: 0.22, blue: 0.55, alpha: 1.0)),
        commands: .init(color: NSColor(red: 0.38, green: 0.28, blue: 0.52, alpha: 1.0)),
        types: .init(color: NSColor(red: 0.13, green: 0.05, blue: 0.72, alpha: 1.0)),
        attributes: .init(color: NSColor(red: 0.52, green: 0.35, blue: 0.20, alpha: 1.0)),
        variables: .init(color: NSColor(red: 0.38, green: 0.28, blue: 0.52, alpha: 1.0)),
        values: .init(color: NSColor(red: 0.38, green: 0.28, blue: 0.52, alpha: 1.0)),
        numbers: .init(color: NSColor(red: 0.13, green: 0.05, blue: 0.72, alpha: 1.0)),
        strings: .init(color: NSColor(red: 0.18, green: 0.55, blue: 0.42, alpha: 1.0)),
        characters: .init(color: NSColor(red: 0.13, green: 0.05, blue: 0.72, alpha: 1.0)),
        comments: .init(color: NSColor(red: 0.42, green: 0.46, blue: 0.50, alpha: 1.0))
    )
}
#endif
