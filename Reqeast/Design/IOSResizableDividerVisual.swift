//
//  IOSResizableDividerVisual.swift
//  Reqeast
//

#if !os(macOS)
import SwiftUI

struct IOSResizableDividerVisual: View {
    let tint: Color?
    let isLoading: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, isLoading ? Color.accentColor.opacity(0.25) : tint?.opacity(0.15) ?? .black.opacity(0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 4)
            .allowsHitTesting(false)

            if isLoading && !reduceMotion {
                Capsule()
                    .fill(.clear)
                    .frame(width: 48, height: 5)
                    .glassEffect(.regular.tint(Color.accentColor), in: .capsule)
                    .phaseAnimator([0.3, 1.0]) { content, phase in
                        content.opacity(phase)
                    } animation: { _ in
                        .easeInOut(duration: 1)
                    }
            } else if isLoading {
                Capsule()
                    .fill(.clear)
                    .frame(width: 48, height: 5)
                    .glassEffect(.regular.tint(Color.accentColor), in: .capsule)
            } else {
                Capsule()
                    .fill(.clear)
                    .frame(width: 48, height: 5)
                    .glassEffect(.regular.tint(tint ?? Color(.tertiaryLabel)), in: .capsule)
            }
        }
    }
}
#endif
