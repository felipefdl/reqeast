//
//  GrpcUITests.swift
//  ReqeastUITests
//

import XCTest

final class GrpcUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-screenshotMode"]
        app.launch()
        UITestHelpers.waitForDemoData(in: app)
    }

    func testCreateGrpcRequestFromProtocolPicker() throws {
        createGrpcRequest()

        let authorityField = app.textFields["grpc-authority-field"].firstMatch
        XCTAssertTrue(
            authorityField.waitForExistence(timeout: 10),
            "gRPC editor should show authority field after creating request"
        )
    }

    func testGrpcEditorShowsSchemaAndRpcSections() throws {
        createGrpcRequest()

        let authorityField = app.textFields["grpc-authority-field"].firstMatch
        XCTAssertTrue(authorityField.waitForExistence(timeout: 10), "Authority field should exist")

        let schemaHeading = app.staticTexts["Schema"].firstMatch
        XCTAssertTrue(schemaHeading.waitForExistence(timeout: 5), "Schema section should be visible")

        let rpcHeading = app.staticTexts["RPC"].firstMatch
        XCTAssertTrue(rpcHeading.waitForExistence(timeout: 5), "RPC section should be visible")

        // No descriptors yet → manual service/method fields with placeholders.
        let serviceField = app.textFields["helloworld.Greeter"].firstMatch
        let methodField = app.textFields["SayHello"].firstMatch
        XCTAssertTrue(
            serviceField.waitForExistence(timeout: 5) || methodField.waitForExistence(timeout: 3),
            "Manual service/method fields should appear when no descriptors are loaded"
        )
    }

    func testOpenProtoLibrarySheet() throws {
        createGrpcRequest()

        let manageButton = app.buttons["grpc-manage-proto-library"].firstMatch
        XCTAssertTrue(
            manageButton.waitForExistence(timeout: 10),
            "Manage Proto Library control should be visible"
        )
        UITestHelpers.press(manageButton)
        Thread.sleep(forTimeInterval: 0.5)

        let doneButton = app.buttons["grpc-proto-library-done"].firstMatch
        XCTAssertTrue(
            doneButton.waitForExistence(timeout: 10),
            "Proto library sheet should present with Done"
        )

        let emptyTitle = app.staticTexts["No Proto Bundles"].firstMatch
        XCTAssertTrue(
            emptyTitle.waitForExistence(timeout: 5)
                || app.staticTexts["Proto Library"].firstMatch.waitForExistence(timeout: 3),
            "Proto library empty state or title should be visible"
        )

        UITestHelpers.press(doneButton)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(doneButton.exists, "Proto library sheet should dismiss on Done")
    }

    func testBodyModeAndSendControlsPresent() throws {
        createGrpcRequest()

        let bodyHeading = app.staticTexts["Request Body"].firstMatch
        XCTAssertTrue(bodyHeading.waitForExistence(timeout: 10), "Request body section should exist")

        // Prefer the stable identifier; fall back to label/button queries for older builds.
        let bodyModePicker = app.segmentedControls["grpc-body-mode-picker"].firstMatch
        let bodyModeAny = app.descendants(matching: .any)["grpc-body-mode-picker"].firstMatch
        let jsonSegment = app.segmentedControls.buttons["JSON"].firstMatch
        let hexSegment = app.segmentedControls.buttons["Hex"].firstMatch
        let hasBodyMode =
            bodyModePicker.waitForExistence(timeout: 5)
            || bodyModeAny.waitForExistence(timeout: 2)
            || jsonSegment.waitForExistence(timeout: 2)
            || hexSegment.waitForExistence(timeout: 2)
        XCTAssertTrue(hasBodyMode, "Body mode JSON/Hex control should be present")

        let sendButton = app.buttons["grpc-send-button"].firstMatch
        XCTAssertTrue(
            sendButton.waitForExistence(timeout: 5),
            "Unary Send control should be present in the connection bar"
        )
    }

    // MARK: - Helpers

    private func createGrpcRequest() {
        selectProject(named: "Weather API")
        openProtocolPicker()
        selectGrpcProtocol()

        let newRequest = UITestHelpers.requestRow(named: "New gRPC Request", in: app)
        XCTAssertTrue(
            newRequest.waitForExistence(timeout: 10),
            "Protocol picker should create New gRPC Request in sidebar"
        )
        UITestHelpers.press(newRequest)
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func selectProject(named name: String) {
        let projectRow = UITestHelpers.projectRow(named: name, in: app)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "Project \(name) should exist")
        UITestHelpers.press(projectRow)
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func openProtocolPicker() {
        #if os(macOS)
        let newRequestButton = app.buttons["New Request"].firstMatch
        if newRequestButton.waitForExistence(timeout: 5) {
            UITestHelpers.press(newRequestButton)
        } else {
            let menuItem = app.menuBars.menuItems["New Request"].firstMatch
            XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "New Request menu item should exist")
            UITestHelpers.press(menuItem)
        }
        #else
        let newRequestButton = app.buttons["New Request"].firstMatch
        XCTAssertTrue(newRequestButton.waitForExistence(timeout: 5), "New Request button should exist")
        UITestHelpers.press(newRequestButton)
        #endif

        let grpcOption = app.buttons["protocol-picker-grpc"].firstMatch
        XCTAssertTrue(
            grpcOption.waitForExistence(timeout: 10),
            "Protocol picker sheet should appear"
        )
    }

    private func selectGrpcProtocol() {
        let candidates: [XCUIElement] = [
            app.buttons["protocol-picker-grpc"].firstMatch,
            app.descendants(matching: .any)["protocol-picker-grpc"].firstMatch,
        ]

        for candidate in candidates where candidate.waitForExistence(timeout: 3) {
            UITestHelpers.press(candidate)
            Thread.sleep(forTimeInterval: 0.5)
            return
        }

        XCTFail("Could not select gRPC protocol in picker")
    }
}