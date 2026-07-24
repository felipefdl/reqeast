//
//  HttpStatusCodesTests.swift
//  ReqeastTests
//

import Testing
@testable import Reqeast

@Suite("HttpStatusCodes")
struct HttpStatusCodesTests {
    @Test func ok200() {
        let desc = HttpStatusCodes.description(for: 200)
        #expect(desc != nil)
        #expect(desc?.contains("succeeded") == true)
    }

    @Test func notFound404() {
        let desc = HttpStatusCodes.description(for: 404)
        #expect(desc != nil)
        #expect(desc?.contains("not be found") == true)
    }

    @Test func serverError500() {
        let desc = HttpStatusCodes.description(for: 500)
        #expect(desc != nil)
        #expect(desc?.contains("unexpected condition") == true)
    }

    @Test func teapot418() {
        let desc = HttpStatusCodes.description(for: 418)
        #expect(desc != nil)
        #expect(desc?.contains("teapot") == true)
    }

    @Test func unknownCodeReturnsNil() {
        #expect(HttpStatusCodes.description(for: 999) == nil)
    }

    @Test func oneFromEachCategory() {
        #expect(HttpStatusCodes.description(for: 100) != nil)
        #expect(HttpStatusCodes.description(for: 200) != nil)
        #expect(HttpStatusCodes.description(for: 301) != nil)
        #expect(HttpStatusCodes.description(for: 400) != nil)
        #expect(HttpStatusCodes.description(for: 500) != nil)
    }
}
