//
//  MacOSResizableDividerVisual.swift
//  Reqeast
//

#if os(macOS)
import SwiftUI

struct MacOSResizableDividerVisual: View {
    let tint: Color?
    let isLoading: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isLoading && !reduceMotion {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
                .phaseAnimator([0.3, 1.0]) { content, phase in
                    content.opacity(phase)
                } animation: { _ in
                    .easeInOut(duration: 1)
                }
        } else if isLoading {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        } else {
            Rectangle()
                .fill(tint?.opacity(0.3) ?? Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
    }
}
#endif
