//
//  ResizableDivider.swift
//  Reqeast
//

import SwiftUI

struct ResizableDivider: View {
    @Binding var splitRatio: CGFloat
    var totalHeight: CGFloat
    var minRatio: CGFloat = 0.15
    var maxRatio: CGFloat = 0.85
    var tint: Color?
    var isLoading: Bool = false

    @State private var dragStartRatio: CGFloat?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: dividerHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                #if os(macOS)
                MacOSResizableDividerVisual(tint: tint, isLoading: isLoading)
                #else
                IOSResizableDividerVisual(tint: tint, isLoading: isLoading)
                #endif
            }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        let startRatio = dragStartRatio ?? splitRatio
                        if dragStartRatio == nil { dragStartRatio = startRatio }
                        let newRatio = startRatio + value.translation.height / totalHeight
                        splitRatio = min(max(newRatio, minRatio), maxRatio)
                    }
                    .onEnded { _ in
                        dragStartRatio = nil
                    }
            )
            #if os(macOS)
            .pointerStyle(.rowResize)
            #endif
    }

    private var dividerHeight: CGFloat {
        #if os(macOS)
        6
        #else
        12
        #endif
    }
}
