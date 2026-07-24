//
//  MessageHistoryButton.swift
//  Reqeast
//

import SwiftUI

struct MessageHistoryButton: View {
    let history: [MessageHistoryEntry]
    let onSelect: (MessageHistoryEntry) -> Void
    let onClear: () -> Void

    @State private var showingPopover = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        Button(action: { showingPopover.toggle() }) {
            Image(systemName: "clock.arrow.circlepath")
        }
        .buttonStyle(.glass)
        .disabled(history.isEmpty)
        .popover(isPresented: isCompact ? .constant(false) : $showingPopover, arrowEdge: .bottom) {
            popoverContent
        }
        .sheet(isPresented: isCompact ? $showingPopover : .constant(false)) {
            sheetContent
        }
    }

    private var popoverContent: some View {
        VStack(spacing: 0) {
            header

            Divider()

            sortedList
        }
        .frame(width: 400, height: 280)
    }

    private var sheetContent: some View {
        NavigationStack {
            sortedList
                .navigationTitle("Message History")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear", role: .destructive) {
                            onClear()
                            showingPopover = false
                        }
                        .foregroundStyle(.red)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingPopover = false }
                    }
                }
        }
        .presentationDetents([.medium])
    }

    private var header: some View {
        HStack {
            Text("Message History")
                .font(.headline)
            Spacer()
            Button("Clear") {
                onClear()
                showingPopover = false
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(12)
    }

    private var sortedList: some View {
        List(sortedHistory) { entry in
            Button(action: { selectEntry(entry) }) {
                HStack(spacing: 8) {
                    Text(entry.encoding.localizedName)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)

                    Text(entry.text)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(formatTimestamp(entry.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .listStyle(.plain)
    }

    private var sortedHistory: [MessageHistoryEntry] {
        history.sorted { $0.timestamp > $1.timestamp }
    }

    private func selectEntry(_ entry: MessageHistoryEntry) {
        onSelect(entry)
        showingPopover = false
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
