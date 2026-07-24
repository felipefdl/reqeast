//
//  HttpUrlBar.swift
//  Reqeast
//

import SwiftUI

struct HttpUrlBar: View, RequestDataBindable {
    @Bindable var store: ProjectStore
    let request: Request
    var sessionStore: HttpSessionStore
    var execution: HttpExecutionState

    @Binding var showingHistory: Bool
    @Binding var focusTrigger: Bool
    var isReadOnly: Bool = false

    @FocusState private var isUrlFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        if isCompact {
            compactLayout
        } else {
            regularLayout
        }
    }

    // MARK: - Compact Layout (iPhone)

    private var compactLayout: some View {
        HStack(spacing: 8) {
            methodPicker

            urlField

            sendButton
        }
        .padding(12)
        .onChange(of: focusTrigger) {
            isUrlFocused = true
        }
    }

    // MARK: - Regular Layout (macOS / iPad)

    private var regularLayout: some View {
        HStack(spacing: 8) {
            methodPicker

            urlField

            historyButton

            sendButton
        }
        .padding(12)
        .onChange(of: focusTrigger) {
            isUrlFocused = true
        }
    }

    // MARK: - Shared Components

    private var methodPicker: some View {
        Picker("Method", selection: binding(\.method)) {
            ForEach(HttpMethod.allCases, id: \.self) { method in
                Text(method.shortLabel)
                    .foregroundStyle(method.color)
                    .tag(method)
            }
        }
        .labelsHidden()
        .tint(httpData.method.color)
        .fixedSize()
        .disabled(isReadOnly)
    }

    private var urlField: some View {
        TextField("Enter URL", text: binding(\.url))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .focused($isUrlFocused)
            .onSubmit { sendRequest() }
            .devTextInput()
            .disabled(isReadOnly)
            .accessibilityIdentifier("http-request-url-field")
    }

    @ViewBuilder
    private var sendButton: some View {
        if execution.isLoading {
            Button(action: { execution.cancel() }) {
                Text("\u{200B}")
                    .hidden()
                    .overlay { Image(systemName: "stop.fill") }
                    .frame(width: 46)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Cancel request")
        } else {
            Button(action: sendRequest) {
                Text("\u{200B}")
                    .hidden()
                    .overlay { Image(systemName: "paperplane.fill") }
                    .frame(width: 46)
            }
            .buttonStyle(.glassProminent)
            .disabled(httpData.url.isEmpty)
            .accessibilityLabel("Send request")
        }
    }

    private var historyButton: some View {
        Button(action: { showingHistory.toggle() }) {
            Image(systemName: "clock.arrow.circlepath")
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Request history")
        .popover(isPresented: $showingHistory) {
            HttpHistoryPopover(
                history: sessionStore.history,
                onRestore: { data in
                    restoreFromHistory(data)
                    showingHistory = false
                }
            )
        }
    }

    // MARK: - Helpers

    private var httpData: HttpRequestData { readData() }

    func readData() -> HttpRequestData {
        request.httpData ?? HttpRequestData()
    }

    func writeData(_ data: HttpRequestData, to request: inout Request) {
        request.httpData = data
    }

    private func sendRequest() {
        #if !os(macOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        execution.send(
            request: request,
            environment: store.activeEnvironment(for: request.projectId),
            sessionStore: sessionStore
        ) { name in
            store.renameRequest(request, to: name)
        }
    }

    private func restoreFromHistory(_ data: HttpRequestData) {
        var updated = request
        updated.httpData = data
        updated.updatedAt = Date()
        store.updateRequest(updated)
    }

}
