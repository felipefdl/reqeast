//
//  ResetDataSheet.swift
//  Reqeast
//

import SwiftUI

struct ResetDataSheet: View {
    var onConfirm: () throws -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var confirmText = ""
    @State private var failures: [DataResetFailure] = []

    private var isConfirmed: Bool {
        confirmText.trimmingCharacters(in: .whitespaces).uppercased() == "DELETE"
    }

    private var hasFailures: Bool { !failures.isEmpty }

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reset All Data").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                ResetDataSheetContent(
                    failures: failures,
                    confirmText: $confirmText,
                    onSubmit: submitIfConfirmed
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            HStack {
                Button(hasFailures ? "Close" : "Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(hasFailures ? "Retry" : "Reset All Data", action: performReset)
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .disabled(!hasFailures && !isConfirmed)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 480)
    }
    #endif

    #if !os(macOS)
    private var iOSBody: some View {
        NavigationStack {
            Form {
                Section {
                    ResetDataSheetContent(
                        failures: failures,
                        confirmText: $confirmText,
                        onSubmit: submitIfConfirmed
                    )
                }
            }
            .navigationTitle("Reset All Data")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(hasFailures ? "Close" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(hasFailures ? "Retry" : "Reset All Data", action: performReset)
                        .foregroundStyle(.red)
                        .disabled(!hasFailures && !isConfirmed)
                }
            }
        }
    }
    #endif

    private func submitIfConfirmed() {
        if isConfirmed { performReset() }
    }

    private func performReset() {
        do {
            try onConfirm()
            dismiss()
        } catch let error as DataResetError {
            failures = error.failures
        } catch {
            failures = [DataResetFailure(category: .sessionFiles, underlying: error)]
        }
    }
}
