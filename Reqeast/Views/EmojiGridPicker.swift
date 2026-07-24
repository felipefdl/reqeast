//
//  EmojiGridPicker.swift
//  Reqeast
//

import SwiftUI

struct EmojiGridPicker: View {
    @Binding var selection: String?
    var highlightColor: Color

    private static let emojis: [String] = [
        "🚀", "🌐", "🔥", "⚡", "💎", "🎯", "🛠️", "🔑",
        "📡", "🗄️", "📦", "🧪", "🐛", "🤖", "🦾", "💡",
        "📊", "📈", "🔒", "🔓", "🌍", "☁️", "🏠", "🎮",
        "🎨", "🎵", "📸", "💬", "📱", "💻", "🖥️", "⌚",
        "🧩", "🔔", "⭐", "❤️", "🍀", "🌙", "☀️", "🏗️",
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
            Button {
                selection = nil
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selection == nil ? highlightColor.opacity(0.2) : Color.clear)

                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(selection == nil ? highlightColor : .clear, lineWidth: 2)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 36)
            }
            .buttonStyle(.plain)

            ForEach(Self.emojis, id: \.self) { emoji in
                Button {
                    selection = emoji
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selection == emoji ? highlightColor.opacity(0.2) : Color.clear)

                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(selection == emoji ? highlightColor : .clear, lineWidth: 2)

                        Text(emoji)
                            .font(.system(size: 18))
                    }
                    .frame(height: 36)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
