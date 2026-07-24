//
//  SpecImportUITests.swift
//  ReqeastUITests
//

import XCTest

final class SpecImportUITests: XCTestCase {
    private var app: XCUIApplication!
    private var importSheet: XCUIElement?

    private var sheet: XCUIElement { importSheet ?? app }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-screenshotMode", "-specImportUITest"]
        app.launch()
        UITestHelpers.waitForDemoData(in: app)
    }

    func testImportIntoExistingProjectMergesRequests() throws {
        selectProject(named: "Weather API")
        openImportSpecSheet()
        selectPasteSourceTab()
        waitForPasteContent()
        tapContinueAndWaitForPreview()
        revealImportTargetControls()
        selectImportTargetExistingProject()
        #if os(macOS)
        selectExistingProject(named: "Weather API")
        #endif

        let importButton = sheet.buttons["spec-import-import-button"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        UITestHelpers.press(importButton)

        XCTAssertFalse(
            app.buttons["spec-import-cancel-button"].firstMatch.waitForExistence(timeout: 3),
            "Import sheet should dismiss after merge import"
        )

        XCTAssertFalse(
            app.staticTexts["project-OpenAPI 3.1 Petstore"].firstMatch.waitForExistence(timeout: 2),
            "Merge import should not create a new project"
        )

        let importedRequest = UITestHelpers.requestRow(named: "List all pets", in: app)
        let importedRequestLabel = app.staticTexts["List all pets"].firstMatch
        XCTAssertTrue(
            importedRequest.waitForExistence(timeout: 15)
                || importedRequestLabel.waitForExistence(timeout: 2),
            "Merged Weather API project should include imported List all pets request"
        )
    }

    func testQuickImportCreatesPetstoreProjectInSidebar() throws {
        openImportSpecSheet()
        selectPasteSourceTab()
        waitForPasteContent()
        tapContinueAndWaitForPreview()

        let importButton = sheet.buttons["spec-import-import-button"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        UITestHelpers.press(importButton)

        XCTAssertFalse(
            app.buttons["spec-import-cancel-button"].firstMatch.waitForExistence(timeout: 10),
            "Import sheet should dismiss after quick import"
        )

        let importedRequest = UITestHelpers.requestRow(named: "List all pets", in: app)
        XCTAssertTrue(
            importedRequest.waitForExistence(timeout: 15),
            "Quick import should create List all pets request"
        )

        let backButton = app.buttons["Projects"].firstMatch
        if backButton.waitForExistence(timeout: 3) {
            UITestHelpers.press(backButton)
            Thread.sleep(forTimeInterval: 0.5)
        }

        let projectRow = UITestHelpers.projectRow(named: "OpenAPI 3.1 Petstore", in: app)
        XCTAssertTrue(
            projectRow.waitForExistence(timeout: 15),
            "Quick import should create OpenAPI 3.1 Petstore project in sidebar"
        )
    }

    func testPastePreviewShowsDetectedOpenAPI31Format() throws {
        openImportSpecSheet()
        selectPasteSourceTab()
        waitForPasteContent()
        tapContinueAndWaitForPreview()

        let formatElement = sheet.descendants(matching: .any)["spec-import-detected-format"].firstMatch
        XCTAssertTrue(formatElement.waitForExistence(timeout: 10), "Preview should show detected format")
        let formatText = accessibilityText(for: formatElement)
        XCTAssertTrue(
            formatText.localizedCaseInsensitiveContains("OpenAPI"),
            "Detected format should be OpenAPI, got: \(formatText)"
        )

        let opCountElement = sheet.staticTexts["spec-import-operation-count"].firstMatch
        XCTAssertTrue(opCountElement.waitForExistence(timeout: 10), "Preview should show operation count")
        let opCountText = accessibilityText(for: opCountElement)
        XCTAssertTrue(
            opCountText.contains("4"),
            "Petstore 3.1 fixture should preview 4 operations, got: \(opCountText)"
        )
    }

    func testQuickImportPasteFlowShowsBaseUrlInEditor() throws {
        openImportSpecSheet()
        selectPasteSourceTab()
        waitForPasteContent()
        tapContinueAndWaitForPreview()
        XCTAssertTrue(
            sheet.staticTexts["spec-import-operation-count"].firstMatch.waitForExistence(timeout: 10),
            "Preview should show operation count"
        )
        let opCountElement = sheet.staticTexts["spec-import-operation-count"].firstMatch
        let opCountText = accessibilityText(for: opCountElement)
        XCTAssertTrue(
            opCountText.contains("4"),
            "Petstore 3.1 fixture should preview 4 operations, got: \(opCountText)"
        )

        let importButton = sheet.buttons["spec-import-import-button"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        UITestHelpers.press(importButton)

        #if os(iOS)
        let importedRequest = UITestHelpers.requestRow(named: "List all pets", in: app)
        if importedRequest.waitForExistence(timeout: 10) {
            UITestHelpers.press(importedRequest)
            Thread.sleep(forTimeInterval: 0.5)
        }
        #endif

        let urlField = app.textFields["http-request-url-field"].firstMatch
        XCTAssertTrue(urlField.waitForExistence(timeout: 15), "HTTP URL field should appear after import")
        let urlValue = urlField.value as? String ?? ""
        XCTAssertTrue(
            urlValue.contains("{{base_url}}"),
            "Imported request URL should contain {{base_url}}, got: \(urlValue)"
        )
    }

    // MARK: - Helpers

    private func selectProject(named name: String) {
        let projectRow = UITestHelpers.projectRow(named: name, in: app)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "Project \(name) should exist")
        projectRow.tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func revealImportTargetControls() {
        #if os(iOS)
        let maxAttempts = 8
        #else
        let maxAttempts = 4
        #endif
        for _ in 0..<maxAttempts {
            if importTargetButtonVisible() { return }
            scrollImportSheetDown()
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func scrollImportSheetDown() {
        let scrollView = sheet.scrollViews.firstMatch
        if scrollView.waitForExistence(timeout: 1) {
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            start.press(forDuration: 0.15, thenDragTo: end)
            return
        }

        #if os(macOS)
        UITestHelpers.press(sheet)
        app.typeKey(XCUIKeyboardKey.pageDown, modifierFlags: [])
        #else
        sheet.swipeUp()
        #endif
    }

    private func searchScopes() -> [XCUIElement] {
        var scopes: [XCUIElement] = [app]
        if let sheetWindow = importSheet {
            scopes.insert(sheetWindow, at: 0)
        }
        return scopes
    }

    private func importTargetButtonVisible() -> Bool {
        let ids = [
            "spec-import-import-target-existingProject",
            "spec-import-import-target",
            "spec-import-existing-project-picker",
        ]
        for scope in searchScopes() {
            for id in ids {
                if scope.buttons[id].firstMatch.exists { return true }
                if scope.pickers[id].firstMatch.exists { return true }
                if scope.descendants(matching: .any)[id].firstMatch.exists { return true }
            }
            if scope.buttons["Existing project"].firstMatch.exists { return true }
        }
        return false
    }

    private func selectImportTargetExistingProject() {
        if importTargetShowsExistingProjectOptions() { return }

        revealImportTargetControls()

        #if os(iOS)
        let targetPicker = sheet.pickers["spec-import-import-target"].firstMatch
        if targetPicker.waitForExistence(timeout: 5) {
            UITestHelpers.press(targetPicker)
            Thread.sleep(forTimeInterval: 0.3)
            if selectPickerOption(named: "Existing project") {
                Thread.sleep(forTimeInterval: 0.3)
                if importTargetShowsExistingProjectOptions() { return }
            }
        }
        #endif

        var directCandidates: [XCUIElement] = []
        for scope in searchScopes() {
            directCandidates.append(scope.buttons["spec-import-import-target-existingProject"].firstMatch)
            directCandidates.append(scope.descendants(matching: .any)["spec-import-import-target-existingProject"].firstMatch)
            directCandidates.append(scope.buttons["Existing project"].firstMatch)
        }

        for candidate in directCandidates where candidate.waitForExistence(timeout: 3) {
            UITestHelpers.press(candidate)
            Thread.sleep(forTimeInterval: 0.3)
            if importTargetShowsExistingProjectOptions() { return }
        }

        XCTFail("Could not select Existing project import target")
    }

    private func selectExistingProject(named name: String) {
        let optionID = "spec-import-existing-project-\(name)"
        #if os(iOS)
        let maxScrollAttempts = 8
        #else
        let maxScrollAttempts = 4
        #endif

        for _ in 0..<maxScrollAttempts {
            if tapExistingProjectOption(id: optionID, name: name) { return }
            scrollImportSheetDown()
            Thread.sleep(forTimeInterval: 0.2)
        }

        XCTFail("Could not select existing project \(name)")
    }

    @discardableResult
    private func tapExistingProjectOption(id optionID: String, name: String) -> Bool {
        for scope in searchScopes() {
            let directCandidates: [XCUIElement] = [
                scope.buttons[optionID].firstMatch,
                scope.descendants(matching: .any)[optionID].firstMatch,
                scope.buttons[name].firstMatch,
                scope.staticTexts[name].firstMatch,
            ]
            for option in directCandidates where option.waitForExistence(timeout: 1) {
                scrollUntilHittable(option)
                if option.isHittable {
                    UITestHelpers.press(option)
                    Thread.sleep(forTimeInterval: 0.3)
                    return true
                }
            }

            #if os(iOS)
            let iosPicker = scope.pickers["spec-import-existing-project-picker"].firstMatch
            if iosPicker.waitForExistence(timeout: 1) {
                scrollUntilHittable(iosPicker)
                if iosPicker.isHittable {
                    UITestHelpers.press(iosPicker)
                    Thread.sleep(forTimeInterval: 0.3)
                    if selectPickerOption(named: name) {
                        Thread.sleep(forTimeInterval: 0.3)
                        return true
                    }
                }
            }
            #endif

            let pickerCandidates: [XCUIElement] = [
                scope.menuButtons["spec-import-existing-project-picker"].firstMatch,
                scope.popUpButtons["spec-import-existing-project-picker"].firstMatch,
                scope.buttons["spec-import-existing-project-picker"].firstMatch,
                scope.descendants(matching: .any)["spec-import-existing-project-picker"].firstMatch,
            ]

            for picker in pickerCandidates where picker.waitForExistence(timeout: 1) {
                scrollUntilHittable(picker)
                if picker.isHittable {
                    UITestHelpers.press(picker)
                    Thread.sleep(forTimeInterval: 0.2)
                    if selectMenuItem(named: name) {
                        Thread.sleep(forTimeInterval: 0.3)
                        return true
                    }
                }
            }
        }
        return false
    }

    private func scrollUntilHittable(_ element: XCUIElement, maxAttempts: Int = 10) {
        var attempts = 0
        while element.exists && !element.isHittable && attempts < maxAttempts {
            scrollImportSheetDown()
            Thread.sleep(forTimeInterval: 0.25)
            attempts += 1
        }
    }

    @discardableResult
    private func selectPickerOption(named name: String) -> Bool {
        #if os(iOS)
        let wheel = app.pickerWheels.firstMatch
        if wheel.waitForExistence(timeout: 2) {
            wheel.adjust(toPickerWheelValue: name)
            return true
        }
        #endif

        let candidates: [XCUIElement] = [
            app.buttons[name].firstMatch,
            app.staticTexts[name].firstMatch,
            sheet.buttons[name].firstMatch,
            sheet.staticTexts[name].firstMatch,
        ]
        for candidate in candidates where candidate.waitForExistence(timeout: 2) {
            UITestHelpers.press(candidate)
            return true
        }
        return false
    }

    private func importTargetShowsExistingProjectOptions() -> Bool {
        sheet.descendants(matching: .any)["spec-import-existing-project-picker"].firstMatch
            .waitForExistence(timeout: 3)
    }

    @discardableResult
    private func selectMenuItem(named name: String) -> Bool {
        let candidates: [XCUIElement] = [
            app.menuItems[name].firstMatch,
            app.menuBars.menuItems[name].firstMatch,
            app.menus.menuItems[name].firstMatch,
            app.menuBarItems[name].firstMatch,
            sheet.menuItems[name].firstMatch,
        ]
        for item in candidates where item.waitForExistence(timeout: 2) {
            UITestHelpers.press(item)
            return true
        }
        return false
    }

    private func openImportSpecSheet() {
        importSheet = UITestHelpers.openImportSpecSheet(in: app)
    }

    private func selectPasteSourceTab() {
        let pasteTabID = "spec-import-source-tab-paste"
        let candidates: [XCUIElement] = [
            sheet.buttons[pasteTabID].firstMatch,
            sheet.radioButtons[pasteTabID].firstMatch,
            sheet.buttons["Paste"].firstMatch,
            sheet.radioButtons["Paste"].firstMatch,
            sheet.segmentedControls["spec-import-source-picker"].buttons["Paste"].firstMatch,
        ]

        for candidate in candidates {
            if candidate.waitForExistence(timeout: 2) {
                UITestHelpers.press(candidate)
                Thread.sleep(forTimeInterval: 0.3)
                return
            }
        }

        // macOS SwiftUI segmented pickers often expose segments by index only.
        let segmentedControls = sheet.segmentedControls
        if segmentedControls.count > 0 {
            let pasteSegment = segmentedControls.element(boundBy: 0).buttons.element(boundBy: 2)
            if pasteSegment.waitForExistence(timeout: 3) {
                UITestHelpers.press(pasteSegment)
                Thread.sleep(forTimeInterval: 0.3)
                return
            }
        }

        XCTFail("Could not find Paste source tab in Import Spec sheet")
    }

    private func pastePetstoreYAML() {
        let pasteEditor = findPasteEditor()
        XCTAssertNotNil(pasteEditor, "Paste editor should exist")
        guard let pasteEditor else { return }
        UITestHelpers.paste(Self.petstore31YAML, into: pasteEditor, scope: sheet)
    }

    private func findPasteEditor() -> XCUIElement? {
        let candidates = [
            sheet.textViews["spec-import-paste-editor"].firstMatch,
            sheet.scrollViews["spec-import-paste-editor"].firstMatch,
            sheet.descendants(matching: .any)["spec-import-paste-editor"].firstMatch,
        ]
        for candidate in candidates {
            if candidate.waitForExistence(timeout: 5) {
                return candidate
            }
        }
        return nil
    }

    private func waitForPasteContent() {
        let continueButton = sheet.buttons["spec-import-continue-button"].firstMatch
        var attempts = 0
        while attempts < 20 {
            if continueButton.exists && continueButton.isEnabled { return }
            Thread.sleep(forTimeInterval: 0.25)
            attempts += 1
        }
        let byteCount = sheet.staticTexts["spec-import-paste-byte-count"].firstMatch
        let label = byteCount.exists ? accessibilityText(for: byteCount) : "(missing)"
        XCTFail("Paste editor should accept spec content; continue disabled, byte count: \(label)")
    }

    private func accessibilityText(for element: XCUIElement) -> String {
        let label = element.label
        if !label.isEmpty { return label }
        if let value = element.value as? String, !value.isEmpty { return value }
        return ""
    }

    private func tapContinueAndWaitForPreview() {
        let continueButton = sheet.buttons["spec-import-continue-button"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        XCTAssertTrue(continueButton.isEnabled, "Continue should be enabled after pasting spec content")
        UITestHelpers.press(continueButton)
        XCTAssertTrue(
            sheet.staticTexts["spec-import-operation-count"].firstMatch.waitForExistence(timeout: 15),
            "Preview operation count should appear after parsing"
        )
    }

    /// Minimal OpenAPI 3.1 petstore fixture (4 operations).
    private static let petstore31YAML = """
    openapi: 3.1.0
    info:
      title: OpenAPI 3.1 Petstore
      description: Petstore sample for OpenAPI 3.1
      version: 1.0.0
    servers:
      - url: https://petstore31.example.test/v1
    tags:
      - name: pet
      - name: store
    paths:
      /pet:
        get:
          tags:
            - pet
          summary: List all pets
          operationId: listPets
          parameters:
            - name: limit
              in: query
              schema:
                type: integer
                example: 25
          responses:
            "200":
              description: Successful operation
        post:
          tags:
            - pet
          summary: Add a new pet
          operationId: addPet
          requestBody:
            required: true
            content:
              application/json:
                schema:
                  type: object
                  required:
                    - name
                  properties:
                    name:
                      type: string
                      example: Mittens
                    status:
                      type: string
                      enum:
                        - available
                        - pending
                        - sold
                example:
                  name: Mittens
                  status: available
          responses:
            "201":
              description: Created
      /pet/{petId}:
        get:
          tags:
            - pet
          summary: Find pet by ID
          operationId: getPetById
          parameters:
            - name: petId
              in: path
              required: true
              schema:
                type: integer
                example: 42
          responses:
            "200":
              description: Successful operation
      /store/order:
        post:
          tags:
            - store
          summary: Place an order
          operationId: placeOrder
          requestBody:
            required: true
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    quantity:
                      type: integer
                      example: 2
          responses:
            "200":
              description: Successful operation
    """
}