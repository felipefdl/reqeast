//
//  LicensesSettingsView.swift
//  Reqeast
//

import SwiftUI

struct LicensesSettingsView: View {
    private let licenses = LicenseBundle.load()

    var body: some View {
        NavigationStack {
            List(licenses) { entry in
                NavigationLink {
                    LicenseDetailView(entry: entry)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.packageName)
                            .font(.body)
                        HStack(spacing: 8) {
                            Text(entry.packageVersion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.license)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Open Source Licenses")
        }
    }
}

struct LicenseDetailView: View {
    let entry: LicenseEntry

    var body: some View {
        ScrollView {
            Text(entry.displayLicenseText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(entry.packageName)
    }
}
