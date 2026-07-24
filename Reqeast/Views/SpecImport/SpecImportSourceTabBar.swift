//
//  SpecImportSourceTabBar.swift
//  Reqeast
//

import SwiftUI

struct SpecImportSourceTabBar: View {
    @Binding var selection: SpecImportSourceTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SpecImportSourceTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Label(tab.label, systemImage: tab.systemImage)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                        .background(
                            selection == tab ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: .rect(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityIdentifier(SpecImportAccessibility.sourceTab(tab))
            }
        }
        .padding(4)
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Import source")
        .accessibilityIdentifier(SpecImportAccessibility.sourcePicker)
    }
}