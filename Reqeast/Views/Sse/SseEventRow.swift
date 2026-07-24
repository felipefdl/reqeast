//
//  SseEventRow.swift
//  Reqeast
//

import SwiftUI

struct SseEventRow: View {
    let entry: SseEventEntry

    var body: some View {
        if entry.isSystem {
            systemRow
        } else {
            eventRow
        }
    }

    private var systemRow: some View {
        HStack {
            Image(systemName: entry.isError ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(entry.isError ? .red.opacity(0.8) : .secondary)
                .font(.caption2)
            Text(entry.data)
                .font(.system(size: 11))
                .foregroundStyle(entry.isError ? .red.opacity(0.8) : .secondary)
                .textSelection(.enabled)
            Spacer()
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
    }

    private var eventRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.eventType)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15), in: Capsule())

                if let eventId = entry.eventId {
                    Text("id: \(eventId)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }

            Text(entry.data)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 6))
    }
}
