//
//  TcpMessageRow.swift
//  Reqeast
//

import SwiftUI

private enum MessageDisplayMode: String, CaseIterable {
    case json
    case hex
}

struct TcpMessageRow: View {
    let message: SocketMessage

    @State private var displayMode: MessageDisplayMode = .json

    /// JSON/Hex toggle is gRPC-only (`wireHex` is set by the gRPC session path).
    /// TCP/UDP/WS rows must keep `message.displayText` encoding behavior.
    private var supportsDisplayToggle: Bool {
        message.wireHex != nil
    }

    var body: some View {
        switch message.direction {
        case .system:
            systemRow
        case .sent, .received:
            dataRow
        }
    }

    private var systemRow: some View {
        HStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: systemIcon)
                    .font(.system(size: 9))
                Text(message.displayText)
                    .font(.system(size: 11))
                    .textSelection(.enabled)
                Text(message.timestamp.formatted(.dateTime.hour().minute().second()))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(message.isError ? .red.opacity(0.8) : .secondary)
            .padding(.vertical, 4)
            Spacer()
        }
    }

    private var systemIcon: String {
        if message.isError {
            return "exclamationmark.triangle.fill"
        }
        let text = message.displayText.lowercased()
        if text.contains("disconnect") {
            return "xmark.circle"
        } else if text.contains("connected") {
            return "checkmark.circle"
        } else if text.contains("connecting") {
            return "arrow.triangle.2.circlepath"
        } else if text.contains("received") {
            return "arrow.down"
        } else if text.contains("sending") {
            return "arrow.up"
        }
        return "info.circle"
    }

    private var dataRow: some View {
        HStack {
            if message.direction == .sent {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.direction == .sent ? .trailing : .leading, spacing: 4) {
                messageBubble

                if message.truncated == true {
                    Text("Truncated")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    if supportsDisplayToggle {
                        Text(displayMode == .json ? "JSON" : "Hex")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Text(message.timestamp.formatted(.dateTime.hour().minute().second()))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            if message.direction == .received {
                Spacer(minLength: 60)
            }
        }
    }

    @ViewBuilder
    private var messageBubble: some View {
        let bubble = Text(rowDisplayText)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                message.direction == .sent
                    ? Color.blue.opacity(0.2)
                    : Color.secondary.opacity(0.15),
                in: RoundedRectangle(cornerRadius: 12)
            )

        if supportsDisplayToggle {
            bubble.contextMenu { displayModeMenu }
        } else {
            bubble
        }
    }

    @ViewBuilder
    private var displayModeMenu: some View {
        Button {
            displayMode = .json
        } label: {
            if displayMode == .json {
                Label("JSON", systemImage: "checkmark")
            } else {
                Text("JSON")
            }
        }
        Button {
            displayMode = .hex
        } label: {
            if displayMode == .hex {
                Label("Hex", systemImage: "checkmark")
            } else {
                Text("Hex")
            }
        }
    }

    private var rowDisplayText: String {
        // Non-gRPC: respect encoding via displayText (utf8 / hex / base64).
        guard supportsDisplayToggle else {
            return message.displayText
        }
        switch displayMode {
        case .json:
            if let json = String(data: message.data, encoding: .utf8), !json.isEmpty {
                return json
            }
            return message.displayText
        case .hex:
            if let wireHex = message.wireHex, !wireHex.isEmpty {
                return formatHexGroups(wireHex)
            }
            return message.hexString
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
        return groups.joined(separator: " ").uppercased()
    }
}
