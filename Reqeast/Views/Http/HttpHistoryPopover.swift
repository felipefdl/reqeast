//
//  HttpHistoryPopover.swift
//  Reqeast
//

import SwiftUI

struct HttpHistoryPopover: View {
    let history: [RequestHistoryEntry]
    let onRestore: (HttpRequestData) -> Void
    var onDismiss: (() -> Void)?

    private var isSheet: Bool { onDismiss != nil }

    var body: some View {
        if isSheet {
            sheetContent
        } else {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(spacing: 0) {
            Text("Request History")
                .font(.headline)
                .padding(12)

            Divider()

            historyList(compact: false)
        }
        .frame(width: 600, height: 320)
    }

    private var sheetContent: some View {
        NavigationStack {
            historyList(compact: true)
                .navigationTitle("Request History")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onDismiss?() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func historyList(compact: Bool) -> some View {
        if history.isEmpty {
            ContentUnavailableView {
                Label("No History", systemImage: "clock")
                    .foregroundStyle(.secondary)
            } description: {
                Text("History will appear here after sending requests")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(history.reversed()) { entry in
                Button(action: { restoreEntry(entry) }) {
                    if compact {
                        compactRow(entry)
                    } else {
                        fullRow(entry)
                    }
                }
                .disabled(entry.httpData == nil)
            }
            .listStyle(.plain)
        }
    }

    private func fullRow(_ entry: RequestHistoryEntry) -> some View {
        HStack(spacing: 8) {
            Text(entry.method)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(methodColor(entry.method))
                .frame(width: 60, alignment: .leading)

            Text("\(entry.statusCode)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(statusColor(for: entry.statusCode))

            Text(entry.url)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatElapsed(entry.elapsedMs))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(formatTimestamp(entry.timestamp))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func compactRow(_ entry: RequestHistoryEntry) -> some View {
        HStack(spacing: 8) {
            Text(entry.method)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(methodColor(entry.method))
                .frame(width: 44, alignment: .leading)

            Text("\(entry.statusCode)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(statusColor(for: entry.statusCode))

            Text(entry.url)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatElapsed(entry.elapsedMs))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func restoreEntry(_ entry: RequestHistoryEntry) {
        guard let data = entry.httpData else { return }
        onRestore(data)
    }

    private func methodColor(_ method: String) -> Color {
        switch method {
        case "GET":     return .green
        case "POST":    return .orange
        case "PUT":     return .blue
        case "PATCH":   return .purple
        case "DELETE":  return .red
        default:        return .gray
        }
    }

    private func statusColor(for code: Int) -> Color {
        switch code {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        case 500..<600: return .red
        default:        return .secondary
        }
    }

    private func formatElapsed(_ ms: Double) -> String {
        DurationFormat.abbreviated(fromMilliseconds: ms)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return String(localized: "just now")
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
    }
}
