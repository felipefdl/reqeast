//
//  JqFilterStatusLabel.swift
//  Reqeast
//

import SwiftUI

struct JqFilterStatusLabel: View {
    let result: JqFilterResult

    var body: some View {
        switch result {
        case .success(let text):
            let count = text.isEmpty ? 0 : text.components(separatedBy: "\n").count
            HStack {
                Text("\(count) \(count == 1 ? String(localized: "result") : String(localized: "results"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        case .failure(let error):
            HStack {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }
}
