//
//  RequestDataBindable.swift
//  Reqeast
//

import SwiftUI

protocol RequestDataBindable: View {
    associatedtype DataType
    var request: Request { get }
    var store: ProjectStore { get }
    func readData() -> DataType
    func writeData(_ data: DataType, to request: inout Request)
}

extension RequestDataBindable {
    func binding<T>(_ keyPath: WritableKeyPath<DataType, T>) -> Binding<T> {
        Binding(
            get: { readData()[keyPath: keyPath] },
            set: { newValue in
                var updated = request
                var data = readData()
                data[keyPath: keyPath] = newValue
                writeData(data, to: &updated)
                updated.updatedAt = Date()
                store.updateRequest(updated)
            }
        )
    }

    func updateData(_ transform: (inout DataType) -> Void) {
        var updated = request
        var data = readData()
        transform(&data)
        writeData(data, to: &updated)
        updated.updatedAt = Date()
        store.updateRequest(updated)
    }
}
