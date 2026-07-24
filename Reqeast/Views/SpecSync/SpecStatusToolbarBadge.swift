//
//  SpecStatusToolbarBadge.swift
//  Reqeast
//

import SwiftUI

struct SpecStatusToolbarBadge: View {
    let label: String
    /// Localized accessibility value for UI tests and VoiceOver (e.g. "Linked spec, 1 stale").
    let accessibilityState: String
    var systemImage: String = "doc.text"
    var highlightsStaleState: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(highlightsStaleState ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityState)
        .accessibilityIdentifier(SpecSyncAccessibility.toolbarBadge)
    }
}