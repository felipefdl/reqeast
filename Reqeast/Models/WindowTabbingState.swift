//
//  WindowTabbingState.swift
//  Reqeast
//

#if os(macOS)
import AppKit

@MainActor
enum WindowTabbingState {
    static var preferTabs = true
    static var pendingTabTarget: NSWindow?
}
#endif
