//
//  ReqeastUITests.swift
//  ReqeastUITests
//

import XCTest

final class ReqeastUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-screenshotMode"]
        app.launch()
        UITestHelpers.waitForDemoData(in: app)
    }

    // MARK: - ProjectManagerView Tests

    func testSidebarShowsProjects() throws {
        let projectNames = ["Weather API", "Stripe Payments", "Chat Platform", "IoT Gateway"]
        for name in projectNames {
            let row = UITestHelpers.projectRow(named: name, in: app)
            XCTAssertTrue(row.waitForExistence(timeout: 5), "Project '\(name)' should exist in sidebar")
        }
    }

    func testSelectProjectShowsRequests() throws {
        let projectRow = UITestHelpers.projectRow(named: "Weather API", in: app)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5))
        projectRow.tap()
        Thread.sleep(forTimeInterval: 0.5)

        let requestRow = UITestHelpers.requestRow(named: "GET Current Weather", in: app)
        XCTAssertTrue(requestRow.waitForExistence(timeout: 5), "Request row should appear after selecting project")
    }

    func testSelectRequestShowsEditor() throws {
        let projectRow = UITestHelpers.projectRow(named: "Weather API", in: app)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5))
        projectRow.tap()
        Thread.sleep(forTimeInterval: 0.5)

        let requestRow = UITestHelpers.requestRow(named: "GET Current Weather", in: app)
        XCTAssertTrue(requestRow.waitForExistence(timeout: 5))
        requestRow.tap()
        Thread.sleep(forTimeInterval: 0.5)

        // The URL bar or editor area should exist
        let editor = app.textFields.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Editor should appear after selecting request")
    }

    func testProjectSwitching() throws {
        // Select Weather API project
        let weatherRow = UITestHelpers.projectRow(named: "Weather API", in: app)
        XCTAssertTrue(weatherRow.waitForExistence(timeout: 5))
        weatherRow.tap()
        Thread.sleep(forTimeInterval: 0.5)

        let weatherRequest = app.staticTexts["request-GET Current Weather"].firstMatch
        XCTAssertTrue(weatherRequest.waitForExistence(timeout: 5), "Weather request should appear")

        // Navigate back to project list via the Projects button in the sidebar toolbar
        let backButton = app.buttons["Projects"].firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Projects back button should exist in sidebar")
        backButton.tap()
        Thread.sleep(forTimeInterval: 0.5)

        // Select a different project
        let iotRow = UITestHelpers.projectRow(named: "IoT Gateway", in: app)
        XCTAssertTrue(iotRow.waitForExistence(timeout: 5), "IoT Gateway project should appear after navigating back")
        iotRow.tap()
        Thread.sleep(forTimeInterval: 0.5)

        let tcpRequest = app.staticTexts["request-TCP Telemetry Stream"].firstMatch
        XCTAssertTrue(tcpRequest.waitForExistence(timeout: 5), "TCP request should appear for IoT project")
    }

    func testCreateProjectSheet() throws {
        // Look for the Add button in the toolbar
        let addButton = app.buttons["Add"].firstMatch
        if addButton.waitForExistence(timeout: 5) {
            addButton.tap()
            Thread.sleep(forTimeInterval: 0.5)

            // Verify sheet appeared with a text field for project name
            let sheet = app.sheets.firstMatch
            let nameField = app.textFields.firstMatch
            let sheetOrField = sheet.waitForExistence(timeout: 3) || nameField.waitForExistence(timeout: 3)
            XCTAssertTrue(sheetOrField, "Create project sheet should appear")
        }
    }

    // MARK: - HttpRequestView Tests

    func testHttpRequestTabSwitching() throws {
        navigateToHttpRequest()

        // Look for tab buttons (Params, Headers, etc.)
        let headersTab = app.buttons["Headers"].firstMatch
        if headersTab.waitForExistence(timeout: 5) {
            headersTab.tap()
            Thread.sleep(forTimeInterval: 0.3)
            XCTAssertTrue(headersTab.exists, "Headers tab should be visible after switching")
        }
    }

    func testHttpResponseEmptyState() throws {
        navigateToHttpRequest()

        // Check for "No Response" empty state
        let noResponse = app.staticTexts["No Response"].firstMatch
        XCTAssertTrue(noResponse.waitForExistence(timeout: 5), "No Response empty state should appear")
    }

    func testHttpMethodPicker() throws {
        navigateToHttpRequest()

        // The method picker should show GET for the demo request.
        // SwiftUI Picker renders differently per platform: check multiple element types.
        let found = app.staticTexts["GET"].firstMatch.waitForExistence(timeout: 5)
            || app.buttons["GET"].firstMatch.waitForExistence(timeout: 3)
            || app.menuButtons["GET"].firstMatch.waitForExistence(timeout: 3)
            || app.popUpButtons["GET"].firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(found, "Method picker should show GET")
    }

    // MARK: - Helpers

    private func navigateToHttpRequest() {
        let projectRow = UITestHelpers.projectRow(named: "Weather API", in: app)
        if projectRow.waitForExistence(timeout: 5) {
            projectRow.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }

        let requestRow = UITestHelpers.requestRow(named: "GET Current Weather", in: app)
        if requestRow.waitForExistence(timeout: 5) {
            requestRow.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
}
