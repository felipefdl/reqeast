//
//  HttpNetworkPopover.swift
//  Reqeast
//

import SwiftUI

struct HttpNetworkPopover: View {
    let response: HttpResponseData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            popoverSection(String(localized: "Connection")) {
                copyableRow(String(localized: "HTTP Version"), response.httpVersion)
                if let addr = response.remoteAddr {
                    copyableRow(String(localized: "Remote Address"), addr)
                }
            }

            if let cert = response.certificate {
                Divider()
                popoverSection(String(localized: "Certificate")) {
                    if let subject = cert.subjectCn {
                        copyableRow(String(localized: "Subject"), subject)
                    }
                    if let issuer = cert.issuerCn {
                        copyableRow(String(localized: "Issuer"), issuer)
                    }
                    if let until = cert.validUntil {
                        copyableRow(String(localized: "Valid Until"), until)
                    }
                }
            }

            if !response.redirectChain.isEmpty {
                Divider()
                popoverSection(String(localized: "Redirects")) {
                    // Indices, not \.self: a redirect loop repeats identical (url, status)
                    // entries, and duplicate Hashable identities make ForEach drop rows.
                    ForEach(response.redirectChain.indices, id: \.self) { index in
                        let entry = response.redirectChain[index]
                        HStack(spacing: 6) {
                            Text("\(entry.statusCode)")
                                .font(.system(.caption, design: .monospaced, weight: .medium))
                                .foregroundStyle(.blue)
                            Text(entry.url)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: 400)
    }

    private func popoverSection<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            content()
        }
    }

    private func copyableRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Button {
                PlatformClipboard.copy(value)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help("Copy")
        }
    }
}
