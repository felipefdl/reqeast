//
//  HttpAuthOAuth2Editor.swift
//  Reqeast
//

import SwiftUI

struct HttpAuthOAuth2Editor: View {
    @Binding var authToken: String
    @Binding var authOAuth2GrantType: String
    @Binding var authOAuth2AuthURL: String
    @Binding var authOAuth2TokenURL: String
    @Binding var authOAuth2Scopes: String

    private var grantTypeSelection: Binding<OAuth2GrantType> {
        Binding(
            get: { OAuth2GrantType(rawValue: authOAuth2GrantType) ?? .clientCredentials },
            set: { authOAuth2GrantType = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OAuth 2.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Configure OAuth2 endpoints and scopes. Token acquisition is not automated yet.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Picker("Grant Type", selection: grantTypeSelection) {
                ForEach(OAuth2GrantType.allCases, id: \.self) { grantType in
                    Text(grantType.localizedName).tag(grantType)
                }
            }
            .tint(.primary)

            oauthField(title: "Authorization URL", text: $authOAuth2AuthURL)
            oauthField(title: "Token URL", text: $authOAuth2TokenURL)
            oauthField(title: "Scopes", text: $authOAuth2Scopes)

            VStack(alignment: .leading, spacing: 4) {
                Text("Access Token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Token", text: $authToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .devTextInput()
            }
        }
    }

    private func oauthField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .devTextInput()
        }
    }
}