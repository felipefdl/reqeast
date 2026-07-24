//
//  WebSocketConnectionBar.swift
//  Reqeast
//

import SwiftUI

struct WebSocketConnectionBar: View, RequestDataBindable {
    @Bindable var store: ProjectStore
    let request: Request
    var sessionStore: WebSocketSessionStore
    @Binding var focusTrigger: Bool

    @FocusState private var isUrlFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var isDisabled: Bool { sessionStore.isConnected || sessionStore.isConnecting }

    private var wsData: WebSocketRequestData { readData() }

    func readData() -> WebSocketRequestData {
        request.webSocketData ?? WebSocketRequestData()
    }

    func writeData(_ data: WebSocketRequestData, to request: inout Request) {
        request.webSocketData = data
    }

    var body: some View {
        if isCompact {
            compactLayout
        } else {
            regularLayout
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 8) {
            TextField("ws:// or wss://", text: binding(\.url))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isUrlFocused)
                .disabled(isDisabled)
                .devTextInput()

            HStack(spacing: 8) {
                TextField("Subprotocols", text: binding(\.subprotocols))
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDisabled)
                    .devTextInput()

                connectButton
            }
        }
        .padding(12)
        .onChange(of: focusTrigger) {
            isUrlFocused = true
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 8) {
            TextField("ws:// or wss://", text: binding(\.url))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isUrlFocused)
                .disabled(isDisabled)
                .devTextInput()

            TextField("Subprotocols", text: binding(\.subprotocols))
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .disabled(isDisabled)
                .devTextInput()

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
            Button(action: { connectWebSocket() }) {
                Text("\u{200B}")
                    .hidden()
                    .overlay { Image(systemName: "play.fill") }
                    .frame(width: 46)
            }
            .buttonStyle(.glassProminent)
            .disabled(wsData.url.isEmpty)
            .accessibilityLabel("Connect")
        }
    }

    private func connectWebSocket() {
        let env = store.activeEnvironment(for: request.projectId)
        let url = EnvironmentVariableService.substitute(wsData.url, environment: env)
        let headers = wsData.headers
            .filter { $0.enabled && !$0.key.isEmpty }
            .map { KeyValuePair(key: $0.key, value: EnvironmentVariableService.substitute($0.value, environment: env), enabled: true) }
        let subprotocols = wsData.subprotocols
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        sessionStore.connect(
            url: url,
            headers: headers,
            subprotocols: subprotocols,
            timeoutSecs: UInt32(wsData.timeoutSeconds),
            allowInsecureTls: wsData.allowInsecureTls
        )
        if !request.isRenamed {
            Task {
                if let name = await RequestNamingService.generateName(
                    method: "", url: url, statusCode: 0, protocolType: "WebSocket"
                ) {
                    store.renameRequest(request, to: name)
                }
            }
        }
    }

}
