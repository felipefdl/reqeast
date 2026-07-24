//
//  GrpcBodyEditor.swift
//  Reqeast
//

import SwiftUI
#if os(macOS)
import CodeEditLanguages
#endif

struct GrpcBodyEditor: View {
    @Binding var bodyMode: GrpcBodyMode
    @Binding var requestBodyJSON: String
    @Binding var requestBodyHex: String
    var bodyValidationError: RequestError?
    var rpcKind: GrpcRpcKind
    var canSend: Bool
    var canHalfClose: Bool
    var canCancel: Bool
    var onSend: () -> Void
    var onHalfClose: () -> Void
    var onCancel: () -> Void

    @State private var editorRefreshId = 0
    @State private var lastEditorContent: String?

    private var showsStreamControls: Bool {
        rpcKind != .unary
    }

    private var activeBodyContent: String {
        switch bodyMode {
        case .json: requestBodyJSON
        case .hex: requestBodyHex
        }
    }

    /// Records local edits so onChange can distinguish typing from external updates.
    private var activeBodyProxy: Binding<String> {
        Binding(
            get: { activeBodyContent },
            set: { newValue in
                lastEditorContent = newValue
                switch bodyMode {
                case .json: requestBodyJSON = newValue
                case .hex: requestBodyHex = newValue
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Request Body")
                    .font(.headline)
                Spacer(minLength: 0)
                Picker("Body mode", selection: $bodyMode) {
                    Text("JSON").tag(GrpcBodyMode.json)
                    Text("Hex").tag(GrpcBodyMode.hex)
                }
                .pickerStyle(.segmented)
                .tint(.primary)
                .frame(maxWidth: 180)
                .accessibilityIdentifier("grpc-body-mode-picker")
            }

            bodyEditor

            if let bodyValidationError {
                Text(bodyValidationError.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if showsStreamControls {
                streamControls
            }
        }
        .onAppear {
            lastEditorContent = activeBodyContent
        }
        .onChange(of: requestBodyJSON) { _, newValue in
            guard bodyMode == .json else { return }
            if lastEditorContent != newValue {
                lastEditorContent = newValue
                editorRefreshId += 1
            }
        }
        .onChange(of: requestBodyHex) { _, newValue in
            guard bodyMode == .hex else { return }
            if lastEditorContent != newValue {
                lastEditorContent = newValue
                editorRefreshId += 1
            }
        }
        .onChange(of: bodyMode) { _, _ in
            lastEditorContent = activeBodyContent
            editorRefreshId += 1
        }
    }

    #if os(macOS)
    private var bodyEditor: some View {
        SourceEditorView(
            text: activeBodyProxy,
            language: bodyMode == .json ? .json : .default
        )
        .frame(minHeight: 140)
        .clipShape(.rect(cornerRadius: 8))
        .id(editorRefreshId)
    }
    #else
    private var bodyEditor: some View {
        SourceEditorView(
            text: activeBodyProxy,
            jsonHighlight: bodyMode == .json
        )
        .frame(minHeight: 140)
        .id(editorRefreshId)
    }
    #endif

    private var streamControls: some View {
        HStack(spacing: 8) {
            if showsSend {
                Button("Send", action: onSend)
                    .buttonStyle(.glassProminent)
                    .disabled(!canSend)
            }

            if showsHalfClose {
                Button("Half-close", action: onHalfClose)
                    .buttonStyle(.glass)
                    .disabled(!canHalfClose)
            }

            if showsCancel {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.glass)
                    .disabled(!canCancel)
            }

            Spacer(minLength: 0)
        }
    }

    private var showsSend: Bool {
        switch rpcKind {
        case .unary: false
        case .serverStreaming, .clientStreaming, .bidirectional: true
        }
    }

    private var showsHalfClose: Bool {
        rpcKind == .clientStreaming || rpcKind == .bidirectional
    }

    private var showsCancel: Bool {
        rpcKind == .serverStreaming || rpcKind == .bidirectional
    }
}
