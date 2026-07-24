//
//  HttpAuthEditor.swift
//  Reqeast
//

import SwiftUI

struct HttpAuthEditor: View {
    @Binding var authType: HttpAuthType
    @Binding var authToken: String
    @Binding var authUsername: String
    @Binding var authPassword: String
    @Binding var authApiKeyName: String
    @Binding var authApiKeyValue: String
    @Binding var authApiKeyLocation: String
    @Binding var authOAuth2GrantType: String
    @Binding var authOAuth2AuthURL: String
    @Binding var authOAuth2TokenURL: String
    @Binding var authOAuth2Scopes: String
    @Binding var authData: HttpAuthData?

    private var safeAuthData: Binding<HttpAuthData> {
        Binding(
            get: { authData ?? HttpAuthData() },
            set: { authData = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Auth Type", selection: $authType) {
                ForEach(HttpAuthType.allCases, id: \.self) { type in
                    if type.isComingSoon {
                        Text("\(type.localizedName) (Coming Soon)").tag(type)
                    } else {
                        Text(type.localizedName).tag(type)
                    }
                }
            }
            .tint(.primary)

            switch authType {
            case .none:
                ContentUnavailableView {
                    Label("No Auth", systemImage: "lock.open")
                        .foregroundStyle(.secondary)
                } description: {
                    Text("This request requires no authentication")
                }

            case .bearer:
                bearerEditor

            case .basic:
                basicEditor

            case .apiKey:
                apiKeyEditor

            case .jwtBearer:
                HttpAuthJwtEditor(authData: safeAuthData)

            case .hawkAuth:
                HttpAuthHawkEditor(authData: safeAuthData)

            case .awsSignature:
                HttpAuthAwsEditor(authData: safeAuthData)

            case .akamaiEdgeGrid:
                HttpAuthAkamaiEditor(authData: safeAuthData)

            case .oauth2:
                HttpAuthOAuth2Editor(
                    authToken: $authToken,
                    authOAuth2GrantType: $authOAuth2GrantType,
                    authOAuth2AuthURL: $authOAuth2AuthURL,
                    authOAuth2TokenURL: $authOAuth2TokenURL,
                    authOAuth2Scopes: $authOAuth2Scopes
                )

            case .digestAuth, .oauth1, .ntlm:
                HttpAuthComingSoonView(authType: authType)
            }
        }
    }

    private var bearerEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bearer Token")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Token", text: $authToken)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .devTextInput()
        }
    }

    private var basicEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Basic Authentication")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Username", text: $authUsername)
                .textFieldStyle(.roundedBorder)
                .devTextInput()
            SecureField("Password", text: $authPassword)
                .textFieldStyle(.roundedBorder)
                .devTextInput()
        }
    }

    private var apiKeyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Key")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Key Name", text: $authApiKeyName)
                .textFieldStyle(.roundedBorder)
                .devTextInput()
            TextField("Key Value", text: $authApiKeyValue)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .devTextInput()
            Picker("Add to", selection: $authApiKeyLocation) {
                Text("Header").tag("header")
                Text("Query Params").tag("query")
            }
            .tint(.primary)
        }
    }
}
