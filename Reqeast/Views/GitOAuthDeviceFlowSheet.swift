//
//  GitOAuthDeviceFlowSheet.swift
//  Reqeast
//

import SwiftUI

struct GitOAuthDeviceFlowSheet: View {
    let account: GitOAuthAccount
    var onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var session: GitDeviceCodeSession?
    @State private var phase: Phase = .starting
    @State private var errorMessage: String?
    @State private var pollTask: Task<Void, Never>?

    private enum Phase {
        case starting
        case waiting
        case success
        case failed
    }

    var body: some View {
        #if os(macOS)
        macLayout
        #else
        iosLayout
        #endif
    }

    #if os(macOS)
    private var macLayout: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 420, height: 320)
        .onAppear { startDeviceFlow() }
        .onDisappear { pollTask?.cancel() }
    }
    #endif

    private var iosLayout: some View {
        NavigationStack {
            content
                .padding()
                .navigationTitle("Sign in to GitHub")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { cancel() }
                    }
                }
        }
        .presentationDetents([.medium])
        .onAppear { startDeviceFlow() }
        .onDisappear { pollTask?.cancel() }
    }

    private var header: some View {
        HStack {
            Text("Sign in to GitHub")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authorize Reqeast to read private Git repositories for \(account.owner) on \(account.displayHost).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch phase {
            case .starting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Requesting device code…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

            case .waiting:
                if let session {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Enter this code on GitHub:")
                            .font(.subheadline.weight(.medium))

                        Text(session.userCode)
                            .font(.system(.title2, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("git-oauth-user-code")

                        HStack(spacing: 12) {
                            Button("Copy Code") {
                                PlatformClipboard.copy(session.userCode)
                            }
                            .buttonStyle(.glass)

                            Button("Open GitHub") {
                                openURL(session.verificationURIComplete ?? session.verificationURI)
                            }
                            .buttonStyle(.glassProminent)
                        }

                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for authorization…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            case .success:
                Label("GitHub account connected.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)

            case .failed:
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    #if os(macOS)
    private var footer: some View {
        HStack {
            Button("Cancel") { cancel() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if phase == .success {
                Button("Done") {
                    onComplete()
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            } else if phase == .failed {
                Button("Try Again") { startDeviceFlow() }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    #endif

    private func startDeviceFlow() {
        pollTask?.cancel()
        phase = .starting
        errorMessage = nil
        session = nil

        pollTask = Task {
            do {
                let deviceSession = try await GitOAuthService.current.requestDeviceCode(account: account)
                await MainActor.run {
                    session = deviceSession
                    phase = .waiting
                }

                try await GitOAuthService.current.completeDeviceFlow(
                    account: account,
                    session: deviceSession
                )

                await MainActor.run {
                    phase = .success
                    onComplete()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    phase = .failed
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func cancel() {
        pollTask?.cancel()
        dismiss()
    }
}