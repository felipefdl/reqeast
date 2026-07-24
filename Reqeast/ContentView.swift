//
//  ContentView.swift
//  Reqeast
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ProjectManagerView()
            #if os(macOS)
            .frame(minWidth: 750, minHeight: 500)
            #endif
    }
}
