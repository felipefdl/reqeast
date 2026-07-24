//
//  SpecExportPresentation.swift
//  Reqeast
//

import Foundation

#if DEBUG
/// Fallback presenter when menu commands run before `focusedSceneValue(\.exportSpec)` is wired (UITest host).
@MainActor
@Observable
final class SpecExportPresentationState {
    static let shared = SpecExportPresentationState()

    var shouldPresentExportSheet = false
    var pendingTarget: SpecExportTarget?

    func requestExportSheet(project: Project, kind: SpecExportKind) {
        pendingTarget = SpecExportTarget(project: project, kind: kind)
        shouldPresentExportSheet = true
    }
}
#endif