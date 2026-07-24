//
//  JqFilterHelpIOSView.swift
//  Reqeast
//

#if !os(macOS)
import SwiftUI

struct JqFilterHelpIOSView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(JqFilterHelpSection.all) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            HStack {
                                Text(item.expression)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                                    .textSelection(.enabled)
                                Spacer(minLength: 12)
                                Text(item.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("jq Filter Reference")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
#endif
