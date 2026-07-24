//
//  SseEventLog.swift
//  Reqeast
//

import SwiftUI

struct SseEventLog: View {
    let events: [SseEventEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(events) { entry in
                        SseEventRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: events.count) { _, _ in
                if let last = events.last {
                    withAnimation(BrandTheme.springSnappy) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView {
                        Label("No SSE Events", systemImage: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.secondary)
                    } description: {
                        Text("Connect to an event source to start receiving events")
                    }
                }
            }
        }
    }
}
