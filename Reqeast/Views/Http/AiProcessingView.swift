//
//  AiProcessingView.swift
//  Reqeast
//

import SwiftUI

struct AiProcessingView: View {
    var colors: [Color] = AiOrbBadge.siriColors

    @State private var rotating = false
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                // Outer glow
                Circle()
                    .fill(glowGradient)
                    .frame(width: 100, height: 100)
                    .blur(radius: 30)
                    .opacity(pulsing ? 0.6 : 0.3)

                // Main orb
                Circle()
                    .fill(orbGradient)
                    .frame(width: 56, height: 56)
                    .shadow(color: colors[1].opacity(0.5), radius: pulsing ? 20 : 10)
                    .scaleEffect(pulsing ? 1.08 : 0.95)
                    .rotationEffect(.degrees(rotating ? 360 : 0))
            }
            Text("Parsing with Apple Intelligence...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startAnimations() }
        .onDisappear { stopAnimations() }
    }

    private var orbGradient: AngularGradient {
        AngularGradient(colors: colors, center: .center)
    }

    private var glowGradient: RadialGradient {
        RadialGradient(
            colors: [colors[0].opacity(0.5), colors[1].opacity(0.3), .clear],
            center: .center,
            startRadius: 5,
            endRadius: 60
        )
    }

    private func startAnimations() {
        guard !reduceMotion else {
            pulsing = true
            return
        }
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            rotating = true
        }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulsing = true
        }
    }

    private func stopAnimations() {
        rotating = false
        pulsing = false
    }
}
