//
//  HttpResponseCookiesView.swift
//  Reqeast
//

import SwiftUI

struct HttpResponseCookiesView: View {
    let cookies: [StoredCookie]

    var body: some View {
        if cookies.isEmpty {
            ContentUnavailableView {
                Label("No Cookies", systemImage: "tray")
                    .foregroundStyle(.secondary)
            } description: {
                Text("No Set-Cookie headers in response")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(cookies) { cookie in
                        cookieRow(cookie)
                        if cookie.id != cookies.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func cookieRow(_ cookie: StoredCookie) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(cookie.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Text("=")
                    .foregroundStyle(.secondary)
                Text(cookie.value)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 12) {
                Label(cookie.domain, systemImage: "globe")
                Label(cookie.path, systemImage: "folder")
                if cookie.secure {
                    Label("Secure", systemImage: "lock.fill")
                }
                if cookie.httpOnly {
                    Label("HttpOnly", systemImage: "eye.slash")
                }
                if let sameSite = cookie.sameSite {
                    Label(sameSite, systemImage: "arrow.left.arrow.right")
                }
                if let expires = cookie.expires {
                    Label(expires, systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
