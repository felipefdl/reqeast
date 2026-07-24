//
//  ProtocolPickerSheet.swift
//  Reqeast
//

import SwiftUI

struct ProtocolPickerSheet: View {
    var onSelect: (RequestType) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    private static let descriptions: [RequestType: LocalizedStringKey] = [
        .http: "Send requests to REST APIs, GraphQL endpoints, and web services",
        .tcp: "Open persistent socket connections with optional TLS encryption",
        .udp: "Send and receive datagrams for connectionless protocols",
        .webSocket: "Full-duplex communication over a single persistent connection",
        .sse: "Receive real-time server-sent events over HTTP",
        .grpc: "Call gRPC services with protobuf messages over HTTP/2",
    ]

    private static let options: [RequestType] = [.http, .tcp, .udp, .webSocket, .sse, .grpc]

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    // MARK: - macOS Body

    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Request").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    cardList
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 400, height: 480)
        .onAppear { appeared = true }
    }
    #endif

    // MARK: - iOS Body

    #if !os(macOS)
    private var iOSBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    cardList
                }
                .padding(16)
            }
            .navigationTitle("New Request")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { appeared = true }
    }
    #endif

    // MARK: - Cards

    private var cardList: some View {
        ForEach(Self.options.indices, id: \.self) { index in
            let type = Self.options[index]
            protocolCard(type, description: Self.descriptions[type]!)
                .staggeredEntrance(appeared: appeared, delay: Double(index) * 0.05)
        }
    }

    private func protocolCard(_ type: RequestType, description: LocalizedStringKey) -> some View {
        Button {
            onSelect(type)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: type.iconName)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.localizedName)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("protocol-picker-\(type.rawValue)")
    }
}
