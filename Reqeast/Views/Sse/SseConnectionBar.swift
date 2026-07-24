//
//  SseConnectionBar.swift
//  Reqeast
//

import SwiftUI

struct SseConnectionBar: View, RequestDataBindable {
    @Bindable var store: ProjectStore
    let request: Request
    var sessionStore: SseSessionStore
    @Binding var focusTrigger: Bool

    @FocusState private var isUrlFocused: Bool
    @State private var showingSettings = false
    private var sseData: SseRequestData { readData() }

    func readData() -> SseRequestData {
        request.sseData ?? SseRequestData()
    }

    func writeData(_ data: SseRequestData, to request: inout Request) {
        request.sseData = data
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("https://example.com/events", text: binding(\.url))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isUrlFocused)
                .disabled(sessionStore.isConnected || sessionStore.isConnecting)
                .devTextInput()

            settingsButton

            connectButton
        }
        .padding(12)
        .onChange(of: focusTrigger) {
            isUrlFocused = true
        }
    }

    @ViewBuilder
    private var connectButton: some View {
        if sessionStore.isConnecting {
            Button(action: { sessionStore.disconnect() }) {
                Text("\u{200B}")
                    .hidden()
                    .overlay { Image(systemName: "stop.fill") }
                    .frame(width: 46)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Cancel connection")
        } else if sessionStore.isConnected {
            Button(action: { sessionStore.disconnect() }) {
                Text("\u{200B}")
                    .hidden()
                    .overlay { Image(systemName: "stop.fill") }
                    .frame(width: 46)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Disconnect")
        } else {
            Button(action: { connectSse() }) {
                Text("\u{200B}")
                    .hidden()
                    .overlay { Image(systemName: "play.fill") }
                    .frame(width: 46)
            }
            .buttonStyle(.glassProminent)
            .disabled(sseData.url.isEmpty)
            .accessibilityLabel("Connect")
        }
    }

    private var settingsButton: some View {
        Button(action: { showingSettings.toggle() }) {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Connection settings")
        #if os(macOS)
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
            settingsPopover
        }
        #else
        .sheet(isPresented: $showingSettings) {
            settingsSheet
        }
        #endif
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsControls
        }
        .padding(16)
        .frame(width: 280)
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                settingsControls
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSettings = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var settingsControls: some View {
        Toggle("SSL certificate verification", isOn: binding(\.sslVerify))

        Stepper(value: binding(\.timeoutSeconds), in: 0...300) {
            HStack {
                Text("Timeout")
                Spacer()
                Text(sseData.timeoutSeconds == 0 ? "Off" : "\(sseData.timeoutSeconds)s")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func connectSse() {
        let env = store.activeEnvironment(for: request.projectId)
        let url = EnvironmentVariableService.substitute(sseData.url, environment: env)
        let headers = sseData.headers
            .filter { $0.enabled && !$0.key.isEmpty }
            .map { KeyValuePair(key: $0.key, value: EnvironmentVariableService.substitute($0.value, environment: env), enabled: true) }

        sessionStore.connect(
            url: url,
            headers: headers,
            sslVerify: sseData.sslVerify,
            timeoutSecs: UInt32(sseData.timeoutSeconds),
            lastEventId: sessionStore.lastEventId
        )
        if !request.isRenamed {
            Task {
                if let name = await RequestNamingService.generateName(
                    method: "", url: url, statusCode: 0, protocolType: "SSE"
                ) {
                    store.renameRequest(request, to: name)
                }
            }
        }
    }

}
