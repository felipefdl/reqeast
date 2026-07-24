//
//  ReadOnlyAttributedTextView.swift
//  Reqeast
//

#if !os(macOS)
import SwiftUI
import UIKit

struct ReadOnlyAttributedTextView: UIViewRepresentable {
    let text: String
    let highlighter: (String) -> NSAttributedString
    // The highlighter bakes static theme colors into the attributed string, so a light/dark
    // switch must invalidate the skip-guard below even though the text is unchanged.
    @Environment(\.colorScheme) private var colorScheme

    final class Coordinator {
        var lastText: String?
        var lastScheme: ColorScheme?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.keyboardDismissMode = .interactive
        textView.contentInsetAdjustmentBehavior = .scrollableAxes
        textView.contentInset = UIEdgeInsets(top: 8, left: 8, bottom: 40, right: 8)
        textView.attributedText = highlighter(text)
        context.coordinator.lastText = text
        context.coordinator.lastScheme = colorScheme
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Re-assigning attributedText resets the user's selection and scroll position and
        // re-runs the highlighter, so skip updates where neither the content nor the color
        // scheme changed (parent re-renders while typing in the jq filter field hit this
        // path constantly).
        guard context.coordinator.lastText != text || context.coordinator.lastScheme != colorScheme else { return }
        context.coordinator.lastText = text
        context.coordinator.lastScheme = colorScheme
        textView.attributedText = highlighter(text)
    }
}
#endif
