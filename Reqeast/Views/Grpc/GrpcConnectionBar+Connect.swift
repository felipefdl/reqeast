//
//  GrpcConnectionBar+Connect.swift
//  Reqeast
//

import SwiftUI

extension GrpcConnectionBar {
    @ViewBuilder
    var connectButton: some View {
        if let sessionStore {
            if sessionStore.isConnecting {
                stopButton(label: "Cancel connection") {
                    sessionStore.disconnect()
                }
            } else if sessionStore.isConnected {
                stopButton(label: "Disconnect") {
                    sessionStore.disconnect()
                }
            } else {
                Button(action: onConnect) {
                    Text("\u{200B}")
                        .hidden()
                        .overlay { Image(systemName: "play.fill") }
                        .frame(width: 46)
                }
                .buttonStyle(.glassProminent)
                .disabled(!canConnect)
                .accessibilityLabel("Connect")
            }
        }
    }

    func stopButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\u{200B}")
                .hidden()
                .overlay { Image(systemName: "stop.fill") }
                .frame(width: 46)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(label)
    }
}