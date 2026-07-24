//
//  FolderColorPicker.swift
//  Reqeast
//

import SwiftUI

struct FolderColorPicker: View {
    @Binding var selection: FolderColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FolderColor.allCases, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if selection == color {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.localizedName)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
    }
}
