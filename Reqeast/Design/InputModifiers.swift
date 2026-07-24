//
//  InputModifiers.swift
//  Reqeast
//

import SwiftUI

extension Binding where Value == String {
    func strippingNewlines() -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "") }
        )
    }
}

extension View {
    func devTextInput() -> some View {
        #if os(macOS)
        self.autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        #endif
    }
}
