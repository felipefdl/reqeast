//
//  MessageSettingsButton.swift
//  Reqeast
//

import SwiftUI

struct MessageSettingsButton: View {
    @Binding var encoding: DataEncoding
    var lineEnding: Binding<LineEnding>?
    var keepConnected: Binding<Bool>?
    var autoPingInterval: Binding<Int>?
    var allowInsecureTls: Binding<Bool>?
    var timeoutSeconds: Binding<Int>?

    @State private var showingPopover = false

    private static let pingIntervals = [0, 5, 10, 15, 30, 60]

    var body: some View {
        Button(action: { showingPopover.toggle() }) {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.glass)
        #if os(macOS)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            popoverContent
        }
        #else
        .sheet(isPresented: $showingPopover) {
            sheetContent
        }
        #endif
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            encodingControls
            connectionControls
        }
        .padding(16)
        .frame(width: 280)
    }

    private var sheetContent: some View {
        NavigationStack {
            Form {
                Section {
                    encodingControls
                }
                Section {
                    connectionControls
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingPopover = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var encodingControls: some View {
        Picker("Encoding", selection: $encoding) {
            ForEach(DataEncoding.allCases, id: \.self) { enc in
                Text(enc.localizedName).tag(enc)
            }
        }
        .tint(.primary)

        if let lineEnding {
            Picker("Line Ending", selection: lineEnding) {
                ForEach(LineEnding.allCases, id: \.self) { ending in
                    Text(ending.localizedName).tag(ending)
                }
            }
            .tint(.primary)
        }

        if let autoPingInterval {
            Picker("Auto Ping", selection: autoPingInterval) {
                Text("Off").tag(0)
                ForEach(Self.pingIntervals.dropFirst(), id: \.self) { secs in
                    Text("\(secs)s").tag(secs)
                }
            }
            .tint(.primary)
        }
    }

    @ViewBuilder
    private var connectionControls: some View {
        if let keepConnected {
            Toggle("Keep connected after send", isOn: keepConnected)
        }

        if let allowInsecureTls {
            Toggle("Allow insecure TLS", isOn: allowInsecureTls)
        }

        if let timeoutSeconds {
            Stepper(value: timeoutSeconds, in: 1...120) {
                HStack {
                    Text("Timeout")
                    Spacer()
                    Text("\(timeoutSeconds.wrappedValue)s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}
