//
//  GrpcResponseLog.swift
//  Reqeast
//

import SwiftUI

private enum GrpcResponseDisplayMode: String, CaseIterable {
    case json
    case hex
}

struct GrpcResponseLog: View {
    var isLoading: Bool
    var response: GrpcUnaryResponse?
    var error: RequestError?
    var authority: String
    var responseTimestamp: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayMode: GrpcResponseDisplayMode = .json
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            if let response {
                unaryResponseView(response)
            } else if let error {
                ContentUnavailableView {
                    Label(error.localizedTitle, systemImage: error.iconName)
                } description: {
                    Text(error.message)
                        .textSelection(.enabled)
                }
            } else if isLoading {
                loadingView
            } else {
                ContentUnavailableView {
                    Label("No Response", systemImage: "arrow.up.right.and.arrow.down.left")
                        .foregroundStyle(.secondary)
                } description: {
                    if authority.isEmpty {
                        Text("Enter an authority above to get started")
                    } else {
                        #if os(macOS)
                        Text("Press \u{2318}Return to send the request")
                        #else
                        Text("Tap Send to invoke the RPC")
                        #endif
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            if reduceMotion {
                ProgressView()
            } else {
                Image(systemName: "arrow.up.right.and.arrow.down.left")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                    .opacity(pulse ? 0.3 : 0.8)
                    .scaleEffect(pulse ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            }
            Text("Sending request…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            pulse = true
        }
        .onDisappear { pulse = false }
    }

    private func unaryResponseView(_ response: GrpcUnaryResponse) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            statusBar(response)

            if hasResponseBody(response) {
                HStack {
                    Spacer(minLength: 0)
                    Picker("Display", selection: $displayMode) {
                        Text("JSON").tag(GrpcResponseDisplayMode.json)
                        Text("Hex").tag(GrpcResponseDisplayMode.hex)
                    }
                    .pickerStyle(.segmented)
                    .tint(.primary)
                    .frame(maxWidth: 160)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()

            if !hasResponseBody(response) {
                if !response.statusMessage.isEmpty {
                    ScrollView {
                        Text(response.statusMessage)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Empty Response", systemImage: "doc")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HttpResponseReadOnlyEditor(
                    text: responseBodyText(response),
                    mode: displayMode == .json ? .json : .plain,
                    responseTimestamp: responseTimestamp
                )
            }
        }
    }

    private func hasResponseBody(_ response: GrpcUnaryResponse) -> Bool {
        !response.responseJson.isEmpty || !response.responseHex.isEmpty
    }

    private func responseBodyText(_ response: GrpcUnaryResponse) -> String {
        switch displayMode {
        case .json:
            return response.responseJson
        case .hex:
            return formatHexGroups(response.responseHex)
        }
    }

    private func formatHexGroups(_ hex: String) -> String {
        let cleaned = hex.filter { !$0.isWhitespace }
        guard !cleaned.isEmpty else { return hex }
        var groups: [String] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            groups.append(String(cleaned[index..<next]))
            index = next
        }
        return groups.joined(separator: " ")
    }

    private func statusBar(_ response: GrpcUnaryResponse) -> some View {
        HStack(spacing: 8) {
            Text("gRPC \(response.statusCode)")
                .font(.headline)
                .monospacedDigit()
            if !response.statusMessage.isEmpty {
                Text(response.statusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if response.truncated {
                Text("Truncated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(response.statusCode == 0 ? Color.primary : Color.red)
    }
}