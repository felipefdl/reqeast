//
//  CompactCheckboxToggle.swift
//  Reqeast
//

import SwiftUI

struct CompactCheckboxToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            if isOn {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
