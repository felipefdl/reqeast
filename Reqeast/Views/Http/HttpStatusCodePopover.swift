//
//  HttpStatusCodePopover.swift
//  Reqeast
//

import SwiftUI

struct HttpStatusCodePopover: View {
    let statusCode: Int
    let statusText: String
    let statusColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(statusCode)")
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if let description = HttpStatusCodes.description(for: statusCode) {
                Divider()
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: 320)
    }
}
