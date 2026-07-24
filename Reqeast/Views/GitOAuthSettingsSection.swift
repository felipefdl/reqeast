//
//  GitOAuthSettingsSection.swift
//  Reqeast
//

import SwiftUI

struct GitOAuthSettingsSection: View {
    @State private var accounts = GitOAuthAccountRegistry.accounts()
    @State private var owner = ""
    @State private var selectedHost = "github.com"
    @State private var manualToken = ""
    @State private var showingDeviceFlow = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var trustedHosts: [String] {
        ["github.com"] + SafeFetchTrustedHosts.hosts
    }

    private var draftAccount: GitOAuthAccount? {
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOwner.isEmpty else { return nil }
        let host = selectedHost == "github.com" ? nil : selectedHost
        return GitOAuthAccount(provider: .github, owner: trimmedOwner, host: host)
    }

    var body: some View {
        Section {
            if accounts.isEmpty {
                Text("No Git provider tokens configured.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(accounts) { account in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.owner)
                                .font(.body.weight(.medium))
                            Text(account.displayHost)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if GitOAuthService.current.hasStoredToken(for: account) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .help("Token saved on this device")
                        }
                        Button("Remove", role: .destructive) {
                            removeAccount(account)
                        }
                    }
                }
            }

            Picker("Host", selection: $selectedHost) {
                ForEach(trustedHosts, id: \.self) { host in
                    Text(host).tag(host)
                }
            }
            .tint(.primary)

            TextField("Organization or user", text: $owner)
                .textFieldStyle(.roundedBorder)

            SecureField("Personal access token (optional)", text: $manualToken)

            HStack {
                Button("Sign in with GitHub…") {
                    beginDeviceFlow()
                }
                .disabled(draftAccount == nil)

                Button("Save Token") {
                    saveManualToken()
                }
                .disabled(draftAccount == nil || manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Git Provider Tokens")
        } footer: {
            Text("Tokens are stored in Keychain on this device only and are used when refreshing linked Git specs. Sign in with GitHub uses the device authorization flow; you can also paste a personal access token manually.")
        }
        .onAppear { reloadAccounts() }
        .sheet(isPresented: $showingDeviceFlow) {
            if let account = draftAccount {
                GitOAuthDeviceFlowSheet(account: account) {
                    reloadAccounts()
                    statusMessage = String(localized: "GitHub token saved for \(account.owner).")
                    errorMessage = nil
                }
            }
        }
    }

    private func beginDeviceFlow() {
        errorMessage = nil
        statusMessage = nil
        guard draftAccount != nil else { return }
        showingDeviceFlow = true
    }

    private func saveManualToken() {
        guard let account = draftAccount else { return }
        errorMessage = nil
        statusMessage = nil

        do {
            try GitOAuthService.current.saveManualToken(manualToken, account: account)
            manualToken = ""
            reloadAccounts()
            statusMessage = String(localized: "Token saved for \(account.owner).")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func removeAccount(_ account: GitOAuthAccount) {
        errorMessage = nil
        statusMessage = nil
        do {
            try GitOAuthService.current.deleteToken(for: account)
            reloadAccounts()
            statusMessage = String(localized: "Removed token for \(account.owner).")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func reloadAccounts() {
        accounts = GitOAuthAccountRegistry.accounts()
    }
}