//
//  TcpConnectionBar.swift
//  Reqeast
//

import SwiftUI

struct TcpConnectionBar: View, RequestDataBindable {
    @Bindable var store: ProjectStore
    let request: Request
    var sessionStore: TcpSessionStore
    @Binding var focusTrigger: Bool

    @FocusState private var isHostFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var isDisabled: Bool { sessionStore.isConnected || sessionStore.isConnecting }

    private var tcpData: TcpRequestData { readData() }

    func readData() -> TcpRequestData {
        request.tcpData ?? TcpRequestData()
    }

    func writeData(_ data: TcpRequestData, to request: inout Request) {
        request.tcpData = data
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
            TextField("Host", text: binding(\.host))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isHostFocused)
                .disabled(isDisabled)
                .devTextInput()

            HStack(spacing: 8) {
                TextField("Port", text: portBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 80)
                    .disabled(isDisabled)
                    .devTextInput()

                Toggle("TLS", isOn: binding(\.useTls))
                    .fixedSize()
                    .disabled(isDisabled)

                Spacer()

                connectButton
            }
        }
        .padding(12)
        .onChange(of: focusTrigger) {
            isHostFocused = true
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 8) {
            TextField("Host", text: binding(\.host))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isHostFocused)
                .disabled(isDisabled)
                .devTextInput()

            TextField("Port", text: portBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 80)
                .disabled(isDisabled)
                .devTextInput()

            Toggle("TLS", isOn: binding(\.useTls))
                .fixedSize()
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
                .disabled(isDisabled)

            connectButton
        }
        .padding(12)
        .onChange(of: focusTrigger) {
            isHostFocused = true
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
            Button(action: { connectTcp() }) {
                Text("\u{200B}")
                    .hidden()
                    .overlay { Image(systemName: "play.fill") }
                    .frame(width: 46)
            }
            .buttonStyle(.glassProminent)
            .disabled(tcpData.host.isEmpty)
            .accessibilityLabel("Connect")
        }
    }

    private func connectTcp() {
        let env = store.activeEnvironment(for: request.projectId)
        let host = EnvironmentVariableService.substitute(tcpData.host, environment: env)
        sessionStore.connect(host: host, port: tcpData.port, useTls: tcpData.useTls)
        if !request.isRenamed {
            let proto = tcpData.useTls ? "TLS" : "TCP"
            let port = tcpData.port
            Task {
                if let name = await RequestNamingService.generateNameForSocket(
                    protocol: proto, host: host, port: port
                ) {
                    store.renameRequest(request, to: name)
                }
            }
        }
    }

    // MARK: - Bindings

    private var portBinding: Binding<String> {
        Binding(
            get: { String(tcpData.port) },
            set: { newValue in
                if let port = Int(newValue) {
                    updateData { $0.port = port }
                }
            }
        )
    }

}
