//
//  JqHelpButton.swift
//  Reqeast
//

import SwiftUI

struct JqHelpButton: View {
    @State private var showHelp = false

    var body: some View {
        Button {
            showHelp.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .popover(isPresented: $showHelp) {
            JqFilterHelpView()
        }
        #else
        .sheet(isPresented: $showHelp) {
            JqFilterHelpView()
                .presentationDetents([.large])
        }
        #endif
    }
}
