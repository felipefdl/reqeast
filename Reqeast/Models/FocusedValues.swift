//
//  FocusedValues.swift
//  Reqeast
//

import SwiftUI

extension FocusedValues {
    // MARK: - State

    @Entry var selectedProject: Project?
    @Entry var selectedRequest: Request?

    // MARK: - Project Actions

    @Entry var newProject: (() -> Void)?
    @Entry var editProject: (() -> Void)?
    @Entry var deleteProject: ((Project) -> Void)?
    @Entry var duplicateProject: ((Project) -> Void)?
    @Entry var exportProject: ((Project) -> Void)?
    @Entry var exportAllProjects: (() -> Void)?
    @Entry var importProject: (() -> Void)?
    @Entry var importSpec: (() -> Void)?
    @Entry var exportSpecOpenAPI: (() -> Void)?
    @Entry var exportSpecPostman: (() -> Void)?

    // MARK: - Request Actions

    @Entry var newRequest: (() -> Void)?
    @Entry var duplicateRequest: (() -> Void)?
    @Entry var deleteRequest: (() -> Void)?

    // MARK: - Protocol Actions

    @Entry var sendOrConnect: (() -> Void)?
    @Entry var cancelOrDisconnect: (() -> Void)?
    @Entry var clearMessages: (() -> Void)?
    @Entry var focusUrlField: (() -> Void)?

    // MARK: - HTTP Actions

    @Entry var prettifyBody: (() -> Void)?
    @Entry var importRequest: (() -> Void)?
    @Entry var codeSnippet: (() -> Void)?
    @Entry var copyResponseBody: (() -> Void)?
    @Entry var shareResponse: (() -> Void)?
    @Entry var shareResponseDetailed: (() -> Void)?
    @Entry var copyUrl: (() -> Void)?
    @Entry var requestHistory: (() -> Void)?
    @Entry var selectRequestTab: ((Int) -> Void)?

    // MARK: - View Actions

    @Entry var focusRequestFilter: (() -> Void)?
    @Entry var manageEnvironments: (() -> Void)?
    @Entry var resetAllData: (() -> Void)?

    // MARK: - State Flags

    @Entry var canSendOrConnect: Bool?
    @Entry var canCancelOrDisconnect: Bool?
    @Entry var hasResponse: Bool?
    @Entry var isHttpRequest: Bool?
    @Entry var hasMessages: Bool?

    // MARK: - Debug

    #if DEBUG
    @Entry var debugLoadDemoData: (() -> Void)?
    #endif
}
