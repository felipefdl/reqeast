//
//  BrandTheme.swift
//  Reqeast
//

import SwiftUI

enum BrandTheme {
    // MARK: - Brand Colors

    static let brand = Color(red: 64 / 255, green: 145 / 255, blue: 195 / 255)        // #4091C3
    static let brandDark = Color(red: 26 / 255, green: 77 / 255, blue: 107 / 255)     // #1A4D6B
    static let brandLight = Color(red: 130 / 255, green: 196 / 255, blue: 232 / 255)  // #82C4E8

    static let brandGradient = LinearGradient(
        colors: [brandDark, brand, brandLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Animation Curves

    static let springSnappy = Animation.spring(duration: 0.3, bounce: 0.2)
    static let springGentle = Animation.spring(duration: 0.5, bounce: 0.15)
    static let easeQuick = Animation.easeInOut(duration: 0.15)
}
