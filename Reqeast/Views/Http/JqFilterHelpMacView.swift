//
//  JqFilterHelpMacView.swift
//  Reqeast
//

#if os(macOS)
import SwiftUI

struct JqFilterHelpMacView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("jq Filter Reference")
                    .font(.headline)
                Spacer()
            }
            .padding(12)

            List {
                ForEach(JqFilterHelpSection.all) { section in
                    Section {
                        ForEach(section.items) { item in
                            HStack {
                                Text(item.expression)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                                    .textSelection(.enabled)
                                Spacer(minLength: 12)
                                Text(item.description)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text(section.title)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 460, height: 560)
    }
}
#endif
