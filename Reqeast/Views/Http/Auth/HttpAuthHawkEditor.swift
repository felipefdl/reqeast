//
//  HttpAuthHawkEditor.swift
//  Reqeast
//

import SwiftUI

struct HttpAuthHawkEditor: View {
    @Binding var authData: HttpAuthData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hawk Authentication")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Auth ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Auth ID", text: $authData.hawkAuthId)
                    .textFieldStyle(.roundedBorder)
                    .devTextInput()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Auth Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Auth Key", text: $authData.hawkAuthKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .devTextInput()
            }

            Picker("Algorithm", selection: $authData.hawkAlgorithm) {
                ForEach(HawkAlgorithm.allCases, id: \.self) { alg in
                    Text(alg.rawValue).tag(alg)
                }
            }
            .tint(.primary)
        }
    }
}
