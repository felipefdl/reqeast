//
//  SettingsView.swift
//  Reqeast
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultTimeout") private var defaultTimeout: Int = 30
    @AppStorage("followRedirects") private var followRedirects: Bool = true
    @AppStorage("jsonIndentSpaces") private var jsonIndentSpaces: Int = 2
    @AppStorage("maxHistoryEntries") private var maxHistoryEntries: Int = 100
    @AppStorage("strictHttpMode") private var strictHttpMode: Bool = true
    @AppStorage("jqUnquoteStrings") private var jqUnquoteStrings: Bool = true
    #if os(macOS)
    @AppStorage("mcpExportEnabled") private var mcpExportEnabled: Bool = false
    @State private var showingMCPSetup = false
    #endif

    #if !os(macOS)
    var onExportAll: (() -> Void)?
    var onImportProject: (() -> Void)?
    #endif

    #if DEBUG
    var onLoadDemoData: (() -> Void)?
    #endif

    #if !os(macOS)
    @State private var showingResetSheet = false
    #endif

    @State private var trustedHosts = SafeFetchTrustedHosts.hosts
    @State private var newTrustedHost = ""

    var body: some View {
        generalSettings
        #if os(macOS)
        .frame(width: 450, height: 620)
        #else
        .sheet(isPresented: $showingResetSheet) {
            ResetDataSheet {
                try DataResetService.resetAllData(store: .shared)
            }
        }
        #endif
    }

    private var generalSettings: some View {
        Form {
            Section("HTTP Defaults") {
                Stepper("Timeout: \(defaultTimeout)s", value: $defaultTimeout, in: 5...120)
                Toggle("Follow Redirects", isOn: $followRedirects)
                Toggle(isOn: $strictHttpMode) {
                    Text("Strict HTTP Mode")
                    Text("Hides the Body tab for GET, HEAD, and OPTIONS requests")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            #if os(macOS)
            Section("MCP Server") {
                Toggle(isOn: $mcpExportEnabled) {
                    Text("Enable MCP Export")
                    Text("Exports session data for AI tools that support the Model Context Protocol")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Setup Guide...") {
                    showingMCPSetup = true
                }
            }
            .sheet(isPresented: $showingMCPSetup) {
                MCPSetupGuideView()
            }
            #endif

            Section("Editor") {
                Stepper("JSON Indent: \(jsonIndentSpaces) spaces", value: $jsonIndentSpaces, in: 1...8)
                Toggle(isOn: $jqUnquoteStrings) {
                    Text("Unquote jq String Results")
                    Text("Strips surrounding quotes and unescapes characters from jq filter output")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("History") {
                Stepper("Max Entries: \(maxHistoryEntries)", value: $maxHistoryEntries, in: 10...1000, step: 10)
            }

            GitOAuthSettingsSection()

            Section {
                if trustedHosts.isEmpty {
                    Text("No trusted hosts configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(trustedHosts, id: \.self) { host in
                        HStack {
                            Text(host)
                            Spacer()
                            Button("Remove", role: .destructive) {
                                SafeFetchTrustedHosts.removeHost(host)
                                trustedHosts = SafeFetchTrustedHosts.hosts
                            }
                        }
                    }
                }

                HStack {
                    TextField("github.mycompany.com", text: $newTrustedHost)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        addTrustedHost()
                    }
                    .disabled(newTrustedHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Trusted Git Hosts")
            } footer: {
                Text("Required for GitHub Enterprise and self-hosted Git. Trusted hosts may use HTTP and internal IP addresses.")
            }
            .onAppear {
                trustedHosts = SafeFetchTrustedHosts.hosts
            }

            #if !os(macOS)
            Section("Data") {
                if let onExportAll {
                    Button("Export All Projects...") {
                        onExportAll()
                    }
                }
                if let onImportProject {
                    Button("Import Project...") {
                        onImportProject()
                    }
                }
                Button("Clear All Response Cache") {
                    try? SessionPersistenceService.shared.deleteAllSessions()
                }
                Button("Reset All Data...", role: .destructive) {
                    showingResetSheet = true
                }
                #if DEBUG
                if let onLoadDemoData {
                    Button("Load Demo Data") {
                        onLoadDemoData()
                    }
                }
                #endif
            }
            #endif
        }
        .formStyle(.grouped)
    }

    private func addTrustedHost() {
        guard SafeFetchTrustedHosts.addHost(newTrustedHost) != nil else { return }
        newTrustedHost = ""
        trustedHosts = SafeFetchTrustedHosts.hosts
    }

}
