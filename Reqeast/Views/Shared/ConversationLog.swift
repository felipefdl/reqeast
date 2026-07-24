//
//  ConversationLog.swift
//  Reqeast
//

import SwiftUI

struct ConversationLog: View {
    let messages: [SocketMessage]
    let emptyTitle: LocalizedStringKey
    let emptyIcon: String
    let emptyDescription: LocalizedStringKey

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        TcpMessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(BrandTheme.springSnappy) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .overlay {
                if messages.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: emptyIcon)
                            .foregroundStyle(.secondary)
                    } description: {
                        Text(emptyDescription)
                    }
                }
            }
        }
    }
}
