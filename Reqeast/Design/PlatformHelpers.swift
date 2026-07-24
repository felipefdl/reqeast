//
//  PlatformHelpers.swift
//  Reqeast
//

import SwiftUI

/// Runtime check for iPhone. Kept as a free helper so it works from `View`,
/// `ToolbarContent`, and non-SwiftUI call sites alike.
var isPhone: Bool {
    #if os(iOS)
    UIDevice.current.userInterfaceIdiom == .phone
    #else
    false
    #endif
}
