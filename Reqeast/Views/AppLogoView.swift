//
//  AppLogoView.swift
//  Reqeast
//

import SwiftUI

struct AppLogoView: View {
    var size: CGFloat = 72
    var breathing: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var isBreathing = false

    private var breathingScale: CGFloat {
        breathing && isBreathing ? 1.06 : 1.0
    }

    private var logoColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        RLogoShape()
            .fill(logoColor, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
            .scaleEffect(breathingScale)
            .shadow(color: .black.opacity(0.2), radius: size * 0.05, y: size * 0.02)
            .onAppear {
                guard breathing else { return }
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
    }
}

struct AppNameText: View {
    var size: Font = .largeTitle

    var body: some View {
        Text("Reqeast")
            .font(size)
            .fontWeight(.bold)
    }
}
