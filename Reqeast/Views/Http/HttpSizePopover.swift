//
//  HttpSizePopover.swift
//  Reqeast
//

import SwiftUI

struct HttpSizePopover: View {
    let sizeInfo: StoredSizeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sizeSection(String(localized: "Response"), total: sizeInfo.totalResponseSize) {
                sizeRow(String(localized: "Headers"), sizeInfo.responseHeadersSize)
                sizeRow(String(localized: "Body"), sizeInfo.responseBodySize)
                if sizeInfo.isCompressed {
                    sizeRow(String(localized: "Compressed"), sizeInfo.responseCompressedSize)
                }
            }

            Divider()

            sizeSection(String(localized: "Request"), total: sizeInfo.totalRequestSize) {
                sizeRow(String(localized: "Headers"), sizeInfo.requestHeadersSize)
                sizeRow(String(localized: "Body"), sizeInfo.requestBodySize)
            }

            Divider()

            Text("Size values are approximate")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(width: 260)
    }

    private func sizeSection<Content: View>(
        _ title: String, total: Int64, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                Text(formatBytes(total))
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
            }
            content()
        }
    }

    private func sizeRow(_ label: String, _ bytes: Int64) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatBytes(bytes))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
    }
}
