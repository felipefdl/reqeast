//
//  ReqeastApp+Commands.swift
//  Reqeast
//

#if os(macOS)
import SwiftUI

struct ReqeastCommands: Commands {
    let openWindow: OpenWindowAction

    @FocusedValue(\.selectedProject) private var selectedProject
    @FocusedValue(\.selectedRequest) private var selectedRequest

    // Project actions
    @FocusedValue(\.newProject) private var newProject
    @FocusedValue(\.editProject) private var editProject
    @FocusedValue(\.deleteProject) private var deleteProject
    @FocusedValue(\.duplicateProject) private var duplicateProject
    @FocusedValue(\.exportProject) private var exportProject
    @FocusedValue(\.exportAllProjects) private var exportAllProjects
    @FocusedValue(\.importProject) private var importProject
    @FocusedValue(\.importSpec) private var importSpec
    @FocusedValue(\.exportSpecOpenAPI) private var exportSpecOpenAPI
    @FocusedValue(\.exportSpecPostman) private var exportSpecPostman

    // Request actions
    @FocusedValue(\.newRequest) private var newRequest
    @FocusedValue(\.duplicateRequest) private var duplicateRequest
    @FocusedValue(\.deleteRequest) private var deleteRequest

    // Protocol actions
    @FocusedValue(\.sendOrConnect) private var sendOrConnect
    @FocusedValue(\.cancelOrDisconnect) private var cancelOrDisconnect
    @FocusedValue(\.clearMessages) private var clearMessages
    @FocusedValue(\.focusUrlField) private var focusUrlField

    // HTTP actions
    @FocusedValue(\.prettifyBody) private var prettifyBody
    @FocusedValue(\.importRequest) private var importRequest
    @FocusedValue(\.codeSnippet) private var codeSnippet
    @FocusedValue(\.copyResponseBody) private var copyResponseBody
    @FocusedValue(\.shareResponse) private var shareResponse
    @FocusedValue(\.shareResponseDetailed) private var shareResponseDetailed
    @FocusedValue(\.copyUrl) private var copyUrl
    @FocusedValue(\.requestHistory) private var requestHistory
    @FocusedValue(\.selectRequestTab) private var selectRequestTab

    // View actions
    @FocusedValue(\.focusRequestFilter) private var focusRequestFilter
    @FocusedValue(\.manageEnvironments) private var manageEnvironments
    @FocusedValue(\.resetAllData) private var resetAllData

    // State flags
    @FocusedValue(\.canSendOrConnect) private var canSendOrConnect
    @FocusedValue(\.canCancelOrDisconnect) private var canCancelOrDisconnect
    @FocusedValue(\.hasResponse) private var hasResponse
    @FocusedValue(\.isHttpRequest) private var isHttpRequest
    @FocusedValue(\.hasMessages) private var hasMessages

    // Debug
    #if DEBUG
    @FocusedValue(\.debugLoadDemoData) private var debugLoadDemoData
    #endif

    @AppStorage("strictHttpMode") private var strictHttpMode: Bool = true

    var body: some Commands {
        fileMenu
        requestMenu
        viewMenu
        windowMenu
        #if DEBUG
        debugMenu
        #endif
    }

    // MARK: - File Menu

    private var fileMenu: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                WindowTabbingState.preferTabs = false
                WindowTabbingState.pendingTabTarget = nil
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("New Tab") {
                WindowTabbingState.preferTabs = true
                WindowTabbingState.pendingTabTarget = NSApplication.shared.keyWindow
                openWindow(id: "main")
            }
            .keyboardShortcut("t", modifiers: [.command])

            Button("New Project") {
                newProject?()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("New Request") {
                newRequest?()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(selectedProject == nil)

            Button("Edit Project...") {
                editProject?()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(selectedProject == nil)

            Button("Duplicate Project") {
                if let project = selectedProject {
                    duplicateProject?(project)
                }
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(selectedProject == nil)

            Button("Duplicate Request") {
                duplicateRequest?()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(selectedRequest == nil)

            Divider()

            Button(String(localized: "Import Spec...")) {
                if let importSpec {
                    importSpec()
                } else {
                    #if DEBUG
                    SpecImportPresentationState.shared.requestImportSheet()
                    #endif
                }
            }

            Button("Import Project...") {
                importProject?()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Export Project...") {
                if let project = selectedProject {
                    exportProject?(project)
                }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(selectedProject == nil)

            Button(String(localized: "Export as OpenAPI...")) {
                if let exportSpecOpenAPI {
                    exportSpecOpenAPI()
                } else if let project = selectedProject {
                    #if DEBUG
                    SpecExportPresentationState.shared.requestExportSheet(project: project, kind: .openapi)
                    #endif
                }
            }
            .disabled(selectedProject == nil)

            Button(String(localized: "Export as Postman...")) {
                if let exportSpecPostman {
                    exportSpecPostman()
                } else if let project = selectedProject {
                    #if DEBUG
                    SpecExportPresentationState.shared.requestExportSheet(project: project, kind: .postman)
                    #endif
                }
            }
            .disabled(selectedProject == nil)

            Button("Export All Projects...") {
                exportAllProjects?()
            }
            .disabled(exportAllProjects == nil)

            Button("Import Request...") {
                importRequest?()
            }
            .keyboardShortcut("i", modifiers: [.command])
            .disabled(isHttpRequest != true)

            Button("Code Snippet...") {
                codeSnippet?()
            }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(isHttpRequest != true)

            Divider()

            Button("Delete Project") {
                if let project = selectedProject {
                    deleteProject?(project)
                }
            }
            .disabled(selectedProject == nil)

            Button("Delete Request") {
                deleteRequest?()
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(selectedRequest == nil)

            Divider()

            Button("Clear Response Cache") {
                try? SessionPersistenceService.shared.deleteAllSessions()
            }

            Button("Reset All Data...") {
                resetAllData?()
            }
        }
    }

    // MARK: - Request Menu

    private var requestMenu: some Commands {
        CommandMenu("Request") {
            Button("Send") {
                sendOrConnect?()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(canSendOrConnect != true)

            Button("Cancel") {
                cancelOrDisconnect?()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(canCancelOrDisconnect != true)

            Divider()

            Button("Focus URL") {
                focusUrlField?()
            }
            .keyboardShortcut("l", modifiers: [.command])
            .disabled(selectedRequest == nil)

            Button("Copy Response Body") {
                copyResponseBody?()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(hasResponse != true)

            Button("Copy Response as Markdown") {
                shareResponse?()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(hasResponse != true)

            Button("Copy Detailed Response as Markdown") {
                shareResponseDetailed?()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift, .option])
            .disabled(hasResponse != true)

            Button("Copy URL") {
                copyUrl?()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(selectedRequest == nil)

            Button("Request History") {
                requestHistory?()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(isHttpRequest != true)

            Button("Clear Messages") {
                clearMessages?()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(hasMessages != true)

            Button("Prettify") {
                prettifyBody?()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
            .disabled(prettifyBody == nil)

            Divider()

            requestTabCommands
        }
    }

    @ViewBuilder
    private var requestTabCommands: some View {
        Button("Params Tab") {
            selectRequestTab?(0)
        }
        .keyboardShortcut("1", modifiers: [.command, .option])
        .disabled(isHttpRequest != true)

        Button("Headers Tab") {
            selectRequestTab?(1)
        }
        .keyboardShortcut("2", modifiers: [.command, .option])
        .disabled(isHttpRequest != true)

        Button("Body Tab") {
            selectRequestTab?(2)
        }
        .keyboardShortcut("3", modifiers: [.command, .option])
        .disabled(isHttpRequest != true)

        Button("Auth Tab") {
            selectRequestTab?(3)
        }
        .keyboardShortcut("4", modifiers: [.command, .option])
        .disabled(isHttpRequest != true)

        Button("Settings Tab") {
            selectRequestTab?(4)
        }
        .keyboardShortcut("5", modifiers: [.command, .option])
        .disabled(isHttpRequest != true)
    }

    // MARK: - View Menu

    private var viewMenu: some Commands {
        CommandMenu("View") {
            Button("Sync") {
                Task { @MainActor in
                    await CloudSyncService.shared.syncChanges()
                }
            }
            .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Toggle("Strict HTTP Mode", isOn: $strictHttpMode)
                .keyboardShortcut("h", modifiers: [.command, .control])

            Divider()

            Button("Focus Request Search") {
                focusRequestFilter?()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(selectedProject == nil)

            Button("Manage Environments...") {
                manageEnvironments?()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(selectedProject == nil)

            Divider()

            Button("Open Source Licenses") {
                openWindow(id: "licenses")
            }
        }
    }

    // MARK: - Window Menu

    private var windowMenu: some Commands {
        CommandGroup(after: .windowArrangement) {
            ForEach(1...9, id: \.self) { index in
                Button("Select Tab \(index)") {
                    selectTab(at: index - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: [.command])
            }
        }
    }

    private func selectTab(at index: Int) {
        guard let keyWindow = NSApplication.shared.keyWindow,
              let tabs = keyWindow.tabbedWindows,
              index < tabs.count else { return }
        tabs[index].makeKeyAndOrderFront(nil)
    }

    // MARK: - Debug Menu

    #if DEBUG
    private var debugMenu: some Commands {
        CommandMenu("Debug") {
            Button("Load Demo Data") {
                debugLoadDemoData?()
            }
        }
    }
    #endif
}
#endif
