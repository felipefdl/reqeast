//
//  JqFilterHelpView.swift
//  Reqeast
//

import SwiftUI

struct JqFilterHelpView: View {
    var body: some View {
        #if os(macOS)
        JqFilterHelpMacView()
        #else
        JqFilterHelpIOSView()
        #endif
    }
}
