//
//  FormDataEntryTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("FormDataEntry")
struct FormDataEntryTests {

    @Test func defaultInit() {
        let entry = FormDataEntry()
        #expect(entry.key == "")
        #expect(entry.value == "")
        #expect(entry.enabled == true)
        #expect(entry.fieldType == .text)
        #expect(entry.fileName == "")
        #expect(entry.mimeType == "")
    }

    @Test func isEmptyWhenAllFieldsEmpty() {
        let entry = FormDataEntry(key: "", value: "", fileName: "")
        #expect(entry.isEmpty == true)
    }

    @Test func isNotEmptyWhenKeyPresent() {
        let entry = FormDataEntry(key: "file", value: "", fileName: "")
        #expect(entry.isEmpty == false)
    }

    @Test func codableRoundTrip() throws {
        let entry = FormDataEntry(
            key: "upload",
            value: "content",
            enabled: false,
            fieldType: .file,
            fileName: "photo.png",
            mimeType: "image/png"
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(FormDataEntry.self, from: data)

        #expect(decoded.key == entry.key)
        #expect(decoded.value == entry.value)
        #expect(decoded.enabled == entry.enabled)
        #expect(decoded.fieldType == entry.fieldType)
        #expect(decoded.fileName == entry.fileName)
        #expect(decoded.mimeType == entry.mimeType)
    }
}
