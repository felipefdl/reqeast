//
//  HttpAuthAkamaiEditor.swift
//  Reqeast
//

import SwiftUI

struct HttpAuthAkamaiEditor: View {
    @Binding var authData: HttpAuthData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Akamai EdgeGrid")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Client Token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Client Token", text: $authData.akamaiClientToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .devTextInput()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Client Secret")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Client Secret", text: $authData.akamaiClientSecret)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .devTextInput()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Access Token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Access Token", text: $authData.akamaiAccessToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .devTextInput()
            }
        }
    }
}
