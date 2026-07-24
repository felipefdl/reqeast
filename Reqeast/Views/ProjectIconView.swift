//
//  ProjectIconView.swift
//  Reqeast
//

import SwiftUI

struct ProjectIconView: View {
    let project: Project
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 8
    var emojiSize: CGFloat = 18
    var symbolSize: CGFloat = 16

    @State private var cachedImage: PlatformImage?
    @State private var didAttemptLoad = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(project.color.color)

            if let cachedImage {
                Image(platformImage: cachedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else if let emoji = project.emoji {
                Text(emoji)
                    .font(.system(size: emojiSize))
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: symbolSize, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: project.iconURL) {
            await loadIcon()
        }
    }

    private func loadIcon() async {
        guard project.iconURL != nil else {
            cachedImage = nil
            return
        }

        let service = ProjectIconService.shared

        if let image = service.loadIcon(for: project.id) {
            cachedImage = image
            return
        }

        if !didAttemptLoad, let urlString = project.iconURL {
            didAttemptLoad = true
            if let image = await service.downloadIcon(from: urlString, for: project.id) {
                cachedImage = image
            }
        }
    }
}
