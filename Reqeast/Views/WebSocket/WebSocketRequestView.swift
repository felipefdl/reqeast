//
//  WebSocketRequestView.swift
//  Reqeast
//

import SwiftUI

struct WebSocketRequestFullView: View, RequestDataBindable {
    @Bindable var store: ProjectStore
    let request: Request

    @State private var messageInput = ""
    @State private var urlFocusTrigger = false

    private var sessionStore: WebSocketSessionStore {
        SessionRegistry.shared.wsSession(for: request.id)
    }

    private var wsData: WebSocketRequestData { readData() }

    func readData() -> WebSocketRequestData {
        request.webSocketData ?? WebSocketRequestData()
    }

    func writeData(_ data: WebSocketRequestData, to request: inout Request) {
        request.webSocketData = data
    }

    var body: some View {
        VStack(spacing: 0) {
            WebSocketConnectionBar(
                store: store,
                request: request,
                sessionStore: sessionStore,
                focusTrigger: $urlFocusTrigger
            )

            Divider()

            messageInputBar

            Divider()

            ConversationLog(
                messages: sessionStore.messages,
                emptyTitle: "No WebSocket Messages",
                emptyIcon: "arrow.left.arrow.right",
                emptyDescription: "Connect to a server to start sending and receiving messages"
            )
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        #if !os(macOS)
        .keyboardDismissToolbar()
        #endif
        #if os(macOS)
        .focusedSceneValue(\.sendOrConnect, {
            let env = store.activeEnvironment(for: request.projectId)
            let url = EnvironmentVariableService.substitute(wsData.url, environment: env)
            let headers = wsData.headers
                .filter { $0.enabled && !$0.key.isEmpty }
                .map {
                    KeyValuePair(
                        key: $0.key,
                        value: EnvironmentVariableService.substitute($0.value, environment: env),
                        enabled: true
                    )
                }
            let subprotocols = wsData.subprotocols
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            sessionStore.connect(
                url: url, headers: headers, subprotocols: subprotocols,
                timeoutSecs: UInt32(wsData.timeoutSeconds), allowInsecureTls: wsData.allowInsecureTls
            )
        })
        .focusedSceneValue(\.cancelOrDisconnect, (sessionStore.isConnected || sessionStore.isConnecting) ? { sessionStore.disconnect() } : nil)
        .focusedSceneValue(\.canSendOrConnect, !sessionStore.isConnected && !sessionStore.isConnecting && !wsData.url.isEmpty)
        .focusedSceneValue(\.canCancelOrDisconnect, sessionStore.isConnected || sessionStore.isConnecting)
        .focusedSceneValue(\.focusUrlField, { urlFocusTrigger.toggle() })
        .focusedSceneValue(\.clearMessages, sessionStore.messages.isEmpty ? nil : { sessionStore.messages.removeAll() })
        .focusedSceneValue(\.hasMessages, !sessionStore.messages.isEmpty)
        .focusedSceneValue(\.hasResponse, false)
        #endif
    }

    private var messageInputBar: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $messageInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { sendMessage() }
                .devTextInput()

            MessageHistoryButton(
                history: wsData.messageHistory,
                onSelect: { entry in
                    messageInput = entry.text
                    updateData { $0.encoding = entry.encoding }
                },
                onClear: {
                    updateData { $0.messageHistory = [] }
                }
            )

            MessageSettingsButton(
                encoding: binding(\.encoding),
                autoPingInterval: binding(\.autoPingInterval),
                allowInsecureTls: binding(\.allowInsecureTls),
                timeoutSeconds: binding(\.timeoutSeconds)
            )
            .disabled(wsData.url.isEmpty)

            Button("Send") {
                sendMessage()
            }
            .buttonStyle(.glassProminent)
            .disabled(!sessionStore.isConnected || messageInput.isEmpty)
        }
        .padding(12)
        .onChange(of: wsData.autoPingInterval) {
            sessionStore.startAutoPing(intervalSeconds: wsData.autoPingInterval)
        }
        .onChange(of: sessionStore.isConnected) {
            if sessionStore.isConnected {
                sessionStore.startAutoPing(intervalSeconds: wsData.autoPingInterval)
            }
        }
    }

    private func sendMessage() {
        guard !messageInput.isEmpty else { return }
        updateData { data in
            MessageHistoryEntry.record(text: messageInput, encoding: wsData.encoding, in: &data.messageHistory)
        }
        sessionStore.sendText(messageInput, encoding: wsData.encoding)
        messageInput = ""
    }

}
