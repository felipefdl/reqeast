//
//  AiOrbBadge.swift
//  Reqeast
//

import SwiftUI

struct AiOrbBadge: View {
    let isActive: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    @State private var rotateGlow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let siriColors: [Color] = [
        Color(red: 0.95, green: 0.25, blue: 0.35),
        Color(red: 0.6, green: 0.3, blue: 0.9),
        Color(red: 0.3, green: 0.5, blue: 0.95),
        Color(red: 0.95, green: 0.55, blue: 0.2),
        Color(red: 0.95, green: 0.25, blue: 0.35),
    ]

    var body: some View {
        Button(action: onTap) {
            Text("Apple Intelligence")
                .font(.caption)
                .fontWeight(.medium)
                .fontDesign(.monospaced)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(badgeBackground)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .onChange(of: isActive) { _, active in
            if active && !reduceMotion {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    rotateGlow = true
                }
            } else {
                rotateGlow = false
            }
        }
    }

    @ViewBuilder
    private var badgeBackground: some View {
        if isActive {
            Capsule()
                .stroke(
                    AngularGradient(colors: Self.siriColors, center: .center, angle: .degrees(rotateGlow ? 360 : 0)),
                    lineWidth: 2
                )
                .background(.fill.quaternary, in: .capsule)
        } else {
            Capsule()
                .fill(.fill.quaternary)
        }
    }
}
