//
//  ResetDataFailureList.swift
//  Reqeast
//

import SwiftUI

struct ResetDataFailureList: View {
    let failures: [DataResetFailure]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Some items could not be deleted:")
                .font(.callout.weight(.semibold))
            ForEach(failures) { failure in
                VStack(alignment: .leading, spacing: 2) {
                    Text(failure.category.localizedLabel)
                        .font(.callout)
                    Text(failure.underlying.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
