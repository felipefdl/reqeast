//
//  UdpRequestView+Bindings.swift
//  Reqeast
//

import SwiftUI

extension UdpRequestFullView {
    var portBinding: Binding<String> {
        Binding(
            get: { String(udpData.port) },
            set: { newValue in
                if let port = Int(newValue) {
                    updateData { $0.port = port }
                }
            }
        )
    }
}
