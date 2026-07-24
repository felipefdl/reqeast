//
//  UdpRequestView.swift
//  Reqeast
//

import SwiftUI

struct UdpRequestFullView: View, RequestDataBindable {
    @Bindable var store: ProjectStore
    let request: Request

    @State private var messageInput = ""
    @State private var hostFocusTrigger = false
    @FocusState private var isHostFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool { horizontalSizeClass == .compact }

    private var sessionStore: UdpSessionStore {
        SessionRegistry.shared.udpSession(for: request.id)
    }

    var udpData: UdpRequestData { readData() }

    func readData() -> UdpRequestData {
        request.udpData ?? UdpRequestData()
    }

    func writeData(_ data: UdpRequestData, to request: inout Request) {
        request.udpData = data
    }

    var body: some View {
        VStack(spacing: 0) {
            configBar

            Divider()

            sendBar

            Divider()

            ConversationLog(
                messages: sessionStore.messages,
                emptyTitle: "No UDP Datagrams",
                emptyIcon: "dot.radiowaves.up.forward",
                emptyDescription: "Start listening to send and receive datagrams"
            )
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        #if !os(macOS)
        .keyboardDismissToolbar()
        #endif
        #if os(macOS)
        .focusedSceneValue(\.sendOrConnect, {
            if !messageInput.isEmpty {
                sendDatagram()
            } else {
                let env = store.activeEnvironment(for: request.projectId)
                let host = EnvironmentVariableService.substitute(udpData.host, environment: env)
                sessionStore.start(host: host, port: udpData.port, bindPort: udpData.bindPort)
            }
        })
        .focusedSceneValue(\.cancelOrDisconnect, sessionStore.isListening ? { sessionStore.stop() } : nil)
        .focusedSceneValue(\.canSendOrConnect, canSendOrConnect)
        .focusedSceneValue(\.canCancelOrDisconnect, sessionStore.isListening)
        .focusedSceneValue(\.focusUrlField, { hostFocusTrigger.toggle() })
        .focusedSceneValue(\.clearMessages, sessionStore.messages.isEmpty ? nil : { sessionStore.messages.removeAll() })
        .focusedSceneValue(\.hasMessages, !sessionStore.messages.isEmpty)
        .focusedSceneValue(\.hasResponse, false)
        #endif
        .onChange(of: hostFocusTrigger) {
            isHostFocused = true
        }
    }

    private var canSendOrConnect: Bool {
        if !messageInput.isEmpty {
            return !sessionStore.isSendingOneShot
        }
        return !sessionStore.isListening && !udpData.host.isEmpty
    }

    private var configBar: some View {
        Group {
            if isCompact {
                compactConfigBar
            } else {
                regularConfigBar
            }
        }
        .padding(12)
    }

    private var compactConfigBar: some View {
        VStack(spacing: 8) {
            TextField("Host", text: binding(\.host))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isHostFocused)
                .disabled(sessionStore.isListening)
                .devTextInput()

            HStack(spacing: 8) {
                TextField("Port", text: portBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 80)
                    .disabled(sessionStore.isListening)
                    .devTextInput()

                Spacer()

                startStopButton
            }
        }
    }

    private var regularConfigBar: some View {
        HStack(spacing: 8) {
            TextField("Host", text: binding(\.host))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isHostFocused)
                .disabled(sessionStore.isListening)
                .devTextInput()

            TextField("Port", text: portBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 80)
                .disabled(sessionStore.isListening)
                .devTextInput()

            startStopButton
        }
    }

    @ViewBuilder
    private var startStopButton: some View {
        if sessionStore.isListening {
            Button(action: { sessionStore.stop() }) {
                Text("\u{200B}")
                    .hidden()
                    .overlay { Image(systemName: "stop.fill") }
                    .frame(width: 46)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Stop listening")
        } else {
            Button(action: { startUdp() }) {
                Text("\u{200B}")
                    .hidden()
                    .overlay { Image(systemName: "play.fill") }
                    .frame(width: 46)
            }
            .buttonStyle(.glassProminent)
            .disabled(udpData.host.isEmpty)
            .accessibilityLabel("Start listening")
        }
    }

    private func startUdp() {
        let env = store.activeEnvironment(for: request.projectId)
        let host = EnvironmentVariableService.substitute(udpData.host, environment: env)
        sessionStore.start(host: host, port: udpData.port, bindPort: udpData.bindPort)
        if !request.isRenamed {
            let port = udpData.port
            Task {
                if let name = await RequestNamingService.generateNameForSocket(
                    protocol: "UDP", host: host, port: port
                ) {
                    store.renameRequest(request, to: name)
                }
            }
        }
    }

    private var sendBar: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $messageInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { sendDatagram() }
                .devTextInput()

            MessageHistoryButton(
                history: udpData.messageHistory,
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
                timeoutSeconds: binding(\.timeoutSeconds)
            )
            .disabled(udpData.host.isEmpty)

            Button("Send") {
                sendDatagram()
            }
            .buttonStyle(.glassProminent)
            .disabled(udpData.host.isEmpty || messageInput.isEmpty || sessionStore.isSendingOneShot)
        }
        .padding(12)
    }

    private func sendDatagram() {
        guard var data = messageInput.data(using: .utf8) else { return }
        data.append(udpData.lineEnding.bytes)
        updateData { data in
            MessageHistoryEntry.record(text: messageInput, encoding: udpData.encoding, in: &data.messageHistory)
        }

        if sessionStore.isListening {
            sessionStore.send(data: data, encoding: udpData.encoding)
        } else {
            let env = store.activeEnvironment(for: request.projectId)
            let host = EnvironmentVariableService.substitute(udpData.host, environment: env)
            sessionStore.sendOneShot(
                host: host,
                port: udpData.port,
                bindPort: udpData.bindPort,
                data: data,
                encoding: udpData.encoding,
                keepConnected: udpData.keepConnected
            )
        }

        messageInput = ""
    }

}
