//
//  DurationFormat.swift
//  Reqeast
//

import Foundation

/// Shared duration formatting for response timings. Centralizes what used to be
/// scattered `String(format: "%.2f ms")` calls in views and share services.
enum DurationFormat {
    /// Renders a millisecond value with the same three-branch rule used across the app:
    /// - below 1 ms → "0.12 ms"
    /// - below 1 s  → "123 ms"
    /// - otherwise  → "1.23 s"
    static func abbreviated(fromMilliseconds ms: Double) -> String {
        let two: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(2))
        let zero: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0))
        if ms < 1 {
            return ms.formatted(two) + " ms"
        }
        if ms < 1000 {
            return ms.formatted(zero) + " ms"
        }
        return (ms / 1000).formatted(two) + " s"
    }
}
