//
//  TcpRequestView.swift
//  Reqeast
//

import SwiftUI

struct TcpRequestFullView: View, RequestDataBindable {
    @Bindable var store: ProjectStore
    let request: Request

    @State private var messageInput = ""
    @State private var hostFocusTrigger = false

    private var sessionStore: TcpSessionStore {
        SessionRegistry.shared.tcpSession(for: request.id)
    }

    private var tcpData: TcpRequestData { readData() }

    func readData() -> TcpRequestData {
        request.tcpData ?? TcpRequestData()
    }

    func writeData(_ data: TcpRequestData, to request: inout Request) {
        request.tcpData = data
    }

    var body: some View {
        VStack(spacing: 0) {
            TcpConnectionBar(
                store: store,
                request: request,
                sessionStore: sessionStore,
                focusTrigger: $hostFocusTrigger
            )

            Divider()

            messageInputBar

            Divider()

            ConversationLog(
                messages: sessionStore.messages,
                emptyTitle: "No TCP Messages",
                emptyIcon: "cable.connector",
                emptyDescription: "Connect to a server to start sending and receiving data"
            )
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        #if !os(macOS)
        .keyboardDismissToolbar()
        #endif
        #if os(macOS)
        .focusedSceneValue(\.sendOrConnect, {
            if !messageInput.isEmpty {
                sendMessage()
            } else {
                let env = store.activeEnvironment(for: request.projectId)
                let host = EnvironmentVariableService.substitute(tcpData.host, environment: env)
                sessionStore.connect(host: host, port: tcpData.port, useTls: tcpData.useTls)
            }
        })
        .focusedSceneValue(\.cancelOrDisconnect, (sessionStore.isConnected || sessionStore.isConnecting) ? { sessionStore.disconnect() } : nil)
        .focusedSceneValue(\.canSendOrConnect, canSendOrConnect)
        .focusedSceneValue(\.canCancelOrDisconnect, sessionStore.isConnected || sessionStore.isConnecting)
        .focusedSceneValue(\.focusUrlField, { hostFocusTrigger.toggle() })
        .focusedSceneValue(\.clearMessages, sessionStore.messages.isEmpty ? nil : { sessionStore.messages.removeAll() })
        .focusedSceneValue(\.hasMessages, !sessionStore.messages.isEmpty)
        .focusedSceneValue(\.hasResponse, false)
        #endif
    }

    private var canSendOrConnect: Bool {
        if !messageInput.isEmpty {
            return !sessionStore.isConnecting && !sessionStore.isSendingOneShot
        }
        return !sessionStore.isConnected && !sessionStore.isConnecting && !tcpData.host.isEmpty
    }

    private var messageInputBar: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $messageInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { sendMessage() }
                .devTextInput()

            MessageHistoryButton(
                history: tcpData.messageHistory,
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
                lineEnding: binding(\.lineEnding),
                keepConnected: binding(\.keepConnected),
                allowInsecureTls: binding(\.allowInsecureTls),
                timeoutSeconds: binding(\.timeoutSeconds)
            )

            .disabled(tcpData.host.isEmpty)

            Button("Send") {
                sendMessage()
            }
            .buttonStyle(.glassProminent)
            .disabled(tcpData.host.isEmpty || messageInput.isEmpty || sessionStore.isConnecting || sessionStore.isSendingOneShot)
        }
        .padding(12)
    }

    private func sendMessage() {
        guard var data = messageInput.data(using: .utf8) else { return }
        data.append(tcpData.lineEnding.bytes)
        updateData { data in
            MessageHistoryEntry.record(text: messageInput, encoding: tcpData.encoding, in: &data.messageHistory)
        }

        if sessionStore.isConnected {
            sessionStore.send(data: data, encoding: tcpData.encoding)
        } else {
            let env = store.activeEnvironment(for: request.projectId)
            let host = EnvironmentVariableService.substitute(tcpData.host, environment: env)
            sessionStore.sendOneShot(
                host: host,
                port: tcpData.port,
                useTls: tcpData.useTls,
                data: data,
                encoding: tcpData.encoding,
                keepConnected: tcpData.keepConnected
            )
        }

        messageInput = ""
    }

}
