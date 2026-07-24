//
//  SpecImportPresentation.swift
//  Reqeast
//

import Foundation

#if DEBUG
/// Fallback presenter when menu commands run before `focusedSceneValue(\.importSpec)` is wired (UITest host).
@MainActor
@Observable
final class SpecImportPresentationState {
    static let shared = SpecImportPresentationState()
    var shouldPresentImportSheet = false

    func requestImportSheet() {
        shouldPresentImportSheet = true
    }
}
#endif