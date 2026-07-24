//
//  GrpcConnectionBar.swift
//  Reqeast
//

import SwiftUI

struct GrpcConnectionBar: View, RequestDataBindable {
    @Bindable var store: ProjectStore
    let request: Request
    var rpcKind: GrpcRpcKind
    var sessionStore: GrpcSessionStore?
    var isSending: Bool
    var canSend: Bool
    var canConnect: Bool
    var onSend: () -> Void
    var onConnect: () -> Void
    @Binding var focusTrigger: Bool

    @FocusState private var isAuthorityFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var grpcData: GrpcRequestData { readData() }
    private var isStreamSessionActive: Bool {
        sessionStore?.isConnected == true || sessionStore?.isConnecting == true
    }
    private var isDisabled: Bool { isSending || isStreamSessionActive }

    func readData() -> GrpcRequestData {
        request.grpcData ?? GrpcRequestData()
    }

    func writeData(_ data: GrpcRequestData, to request: inout Request) {
        request.grpcData = data
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
            authorityField
            HStack(spacing: 8) {
                tlsControls
                Spacer()
                actionButton
            }
        }
        .padding(12)
        .onChange(of: focusTrigger) {
            isAuthorityFocused = true
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 8) {
            authorityField
            tlsControls
            actionButton
        }
        .padding(12)
        .onChange(of: focusTrigger) {
            isAuthorityFocused = true
        }
    }

    private var authorityField: some View {
        TextField("localhost:50051", text: binding(\.authority))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .focused($isAuthorityFocused)
            .disabled(isDisabled)
            .devTextInput()
            .accessibilityIdentifier("grpc-authority-field")
    }

    @ViewBuilder
    private var tlsControls: some View {
        Toggle("TLS", isOn: binding(\.useTls))
            .fixedSize()
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
            .disabled(isDisabled)

        if grpcData.useTls {
            Toggle("Allow insecure TLS", isOn: binding(\.allowInsecureTls))
                .fixedSize()
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
                .disabled(isDisabled)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch rpcKind {
        case .unary:
            sendButton
        case .serverStreaming:
            serverStreamingButton
        case .clientStreaming, .bidirectional:
            connectButton
        }
    }

    private var sendButton: some View {
        Button("Send", action: onSend)
            .buttonStyle(.glassProminent)
            .disabled(!canSend)
            .accessibilityIdentifier("grpc-send-button")
    }

    /// Server streaming starts with a single request body (Send), then shows stop while active.
    @ViewBuilder
    private var serverStreamingButton: some View {
        if let sessionStore {
            if sessionStore.isConnecting {
                stopButton(label: "Cancel stream") {
                    sessionStore.disconnect()
                }
            } else if sessionStore.isConnected {
                stopButton(label: "Stop stream") {
                    sessionStore.disconnect()
                }
            } else {
                sendButton
            }
        } else {
            sendButton
        }
    }

}
