//
//  HttpCookieManager.swift
//  Reqeast
//

import SwiftUI

struct HttpCookieManager: View {
    @Bindable var cookieStore: CookieStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        #if os(macOS)
        .frame(width: 700, height: 450)
        #endif
    }

    private var header: some View {
        HStack {
            Text("Cookie Manager")
                .font(.headline)
            Spacer()
            Text("\(cookieStore.cookies.count) cookies")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var content: some View {
        Group {
            if cookieStore.cookies.isEmpty {
                ContentUnavailableView {
                    Label("No Cookies", systemImage: "tray")
                        .foregroundStyle(.secondary)
                } description: {
                    Text("Cookies from responses will appear here")
                }
            } else {
                cookieList
            }
        }
    }

    private var cookieList: some View {
        List {
            ForEach(cookieStore.cookies) { cookie in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(cookie.name)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        Spacer()
                        Text(cookie.domain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(cookie.value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 8) {
                        Text(cookie.path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if cookie.secure {
                            Label("Secure", systemImage: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if cookie.httpOnly {
                            Text("HttpOnly")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        cookieStore.deleteCookie(cookie)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Clear All", role: .destructive) {
                cookieStore.clearAll()
            }
            .disabled(cookieStore.cookies.isEmpty)
        }
        .padding()
    }
}
