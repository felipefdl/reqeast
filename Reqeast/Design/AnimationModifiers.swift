//
//  AnimationModifiers.swift
//  Reqeast
//

import SwiftUI

// MARK: - Staggered Entrance

struct StaggeredEntrance: ViewModifier {
    let appeared: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (appeared ? 0 : 20))
            .animation(
                reduceMotion ? .none : .easeOut(duration: 0.6).delay(delay),
                value: appeared
            )
    }
}

// MARK: - View Extensions

extension View {
    func staggeredEntrance(appeared: Bool, delay: Double) -> some View {
        modifier(StaggeredEntrance(appeared: appeared, delay: delay))
    }
}
