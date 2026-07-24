//
//  HttpAuthJwtEditor.swift
//  Reqeast
//

import SwiftUI

struct HttpAuthJwtEditor: View {
    @Binding var authData: HttpAuthData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("JWT Bearer")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Algorithm", selection: $authData.jwtAlgorithm) {
                ForEach(JwtAlgorithm.allCases, id: \.self) { alg in
                    Text(alg.rawValue).tag(alg)
                }
            }
            .tint(.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Secret")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Secret key", text: $authData.jwtSecret)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .devTextInput()
            }

            Toggle("Secret is Base64 encoded", isOn: $authData.jwtBase64Encoded)

            VStack(alignment: .leading, spacing: 4) {
                Text("Payload (JSON)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $authData.jwtPayload)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 80)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 8))
                    .devTextInput()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Header Prefix")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Bearer", text: $authData.jwtHeaderPrefix)
                    .textFieldStyle(.roundedBorder)
                    .devTextInput()
            }
        }
    }
}
