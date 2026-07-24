//
//  HttpAuthAwsEditor.swift
//  Reqeast
//

import SwiftUI

struct HttpAuthAwsEditor: View {
    @Binding var authData: HttpAuthData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AWS Signature")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Access Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Access Key", text: $authData.awsAccessKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .devTextInput()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Secret Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Secret Key", text: $authData.awsSecretKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .devTextInput()
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Region")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("us-east-1", text: $authData.awsRegion)
                        .textFieldStyle(.roundedBorder)
                        .devTextInput()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Service")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("s3", text: $authData.awsService)
                        .textFieldStyle(.roundedBorder)
                        .devTextInput()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Session Token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Optional", text: $authData.awsSessionToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .devTextInput()
            }
        }
    }
}
