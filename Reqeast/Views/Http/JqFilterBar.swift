//
//  JqFilterBar.swift
//  Reqeast
//

import SwiftUI

struct JqFilterBar: View {
    @Binding var filterExpression: String
    let filterResult: JqFilterResult?

    @AppStorage("jqUnquoteStrings") private var jqUnquoteStrings = true
    @FocusState private var isFilterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.caption)
                    .foregroundStyle(filterExpression.isEmpty ? .secondary : Color.orange)

                TextField("jq filter (e.g. .data[] | .name)", text: $filterExpression)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(filterExpression.isEmpty ? .primary : Color.orange)
                    .textFieldStyle(.plain)
                    .focused($isFilterFocused)
                    .devTextInput()

                if !filterExpression.isEmpty {
                    Button {
                        jqUnquoteStrings.toggle()
                    } label: {
                        Image(systemName: "quote.closing")
                            .font(.caption)
                            .foregroundStyle(jqUnquoteStrings ? Color.orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Unquote string results")

                    Button {
                        filterExpression = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                JqHelpButton()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if let result = filterResult {
                JqFilterStatusLabel(result: result)
            }

            Divider()
        }
        .onChange(of: isFilterFocused) {
            UIStateStore.shared.isResponseFieldFocused = isFilterFocused
        }
    }
}
