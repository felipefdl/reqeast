//
//  ResetDataConfirmField.swift
//  Reqeast
//

import SwiftUI

struct ResetDataConfirmField: View {
    @Binding var confirmText: String
    var onSubmit: () -> Void

    var body: some View {
        TextField("DELETE", text: $confirmText)
            .onSubmit(onSubmit)
            .devTextInput()
            #if os(macOS)
            .textFieldStyle(.roundedBorder)
            #endif
    }
}
