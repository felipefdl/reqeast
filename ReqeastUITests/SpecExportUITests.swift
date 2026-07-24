//
//  SpecExportUITests.swift
//  ReqeastUITests
//

import XCTest

final class SpecExportUITests: XCTestCase {
    private var app: XCUIApplication!
    private var importSheet: XCUIElement?

    private var sheet: XCUIElement { importSheet ?? app }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-screenshotMode", "-specImportUITest", "-specExportUITest"]
        app.launch()
        UITestHelpers.waitForDemoData(in: app)
    }

    func testExportPetstoreReimportSameOpCount() throws {
        importPetstoreProject()
        exportPetstoreProject()

        openImportSpecSheetForReimport()
        selectPasteSourceTab()
        waitForPasteContent()
        tapContinueAndWaitForPreview()

        let opCountElement = sheet.staticTexts["spec-import-operation-count"].firstMatch
        XCTAssertTrue(opCountElement.waitForExistence(timeout: 10), "Re-import preview should show operation count")
        let opCountText = accessibilityText(for: opCountElement)
        XCTAssertTrue(
            opCountText.contains("4"),
            "Exported petstore re-import should preview 4 operations, got: \(opCountText)"
        )
    }

    // MARK: - Import helpers

    private func importPetstoreProject() {
        openImportSpecSheet()
        selectPasteSourceTab()
        waitForPasteContent()
        tapContinueAndWaitForPreview()

        let importButton = sheet.buttons["spec-import-import-button"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        importButton.tap()

        let importedRequest = UITestHelpers.requestRow(named: "List all pets", in: app)
        XCTAssertTrue(
            importedRequest.waitForExistence(timeout: 15),
            "Petstore import should create List all pets request"
        )
    }

    // MARK: - Export helpers

    private func exportPetstoreProject() {
        #if os(iOS)
        let backButton = app.buttons["Projects"].firstMatch
        if backButton.waitForExistence(timeout: 3) {
            UITestHelpers.press(backButton)
            Thread.sleep(forTimeInterval: 0.5)
        }
        UITestHelpers.exportOpenAPIFromProjectContextMenu(named: "OpenAPI 3.1 Petstore", in: app)
        #else
        exportOpenAPIFromFileMenu()
        #endif
    }

    private func exportOpenAPIFromFileMenu() {
        let fileMenu = app.menuBars.menuBarItems["File"].firstMatch
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 5), "File menu should exist")
        UITestHelpers.press(fileMenu)

        let exportItem = app.menuBars.menuItems["Export as OpenAPI..."].firstMatch
        XCTAssertTrue(exportItem.waitForExistence(timeout: 5), "Export as OpenAPI menu item should exist")
        UITestHelpers.press(exportItem)

        let exportButton = app.buttons[SpecExportAccessibilityID.sheetExportButton].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 10), "Export sheet should expose export button")
        UITestHelpers.press(exportButton)

        XCTAssertFalse(
            app.buttons[SpecExportAccessibilityID.sheetExportButton].firstMatch.waitForExistence(timeout: 5),
            "Export sheet should dismiss after UITest export"
        )
    }

    // MARK: - Import sheet helpers

    private func openImportSpecSheet() {
        importSheet = UITestHelpers.openImportSpecSheet(in: app)
    }

    private func openImportSpecSheetForReimport() {
        #if os(iOS)
        importSheet = UITestHelpers.openImportSpecSheet(in: app)
        #else
        openImportSpecSheetFromFileMenu()
        #endif
    }

    private func openImportSpecSheetFromFileMenu() {
        app.activate()
        Thread.sleep(forTimeInterval: 0.5)

        let fileMenu = app.menuBars.menuBarItems["File"].firstMatch
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 5), "File menu should exist for re-import")
        UITestHelpers.press(fileMenu)

        let importSpecItem = app.menuBars.menuItems["Import Spec..."].firstMatch
        XCTAssertTrue(importSpecItem.waitForExistence(timeout: 5), "Import Spec menu item should exist")
        UITestHelpers.press(importSpecItem)

        XCTAssertTrue(
            app.buttons["spec-import-cancel-button"].firstMatch.waitForExistence(timeout: 15),
            "Import Spec sheet should appear for re-import"
        )
        let sheetWindow = app.windows.containing(.button, identifier: "spec-import-cancel-button").firstMatch
        importSheet = sheetWindow.waitForExistence(timeout: 2) ? sheetWindow : app
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

        for candidate in candidates where candidate.waitForExistence(timeout: 2) {
            UITestHelpers.press(candidate)
            Thread.sleep(forTimeInterval: 0.3)
            return
        }

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

    private func waitForPasteContent() {
        let continueButton = sheet.buttons["spec-import-continue-button"].firstMatch
        var attempts = 0
        while attempts < 20 {
            if continueButton.exists && continueButton.isEnabled { return }
            Thread.sleep(forTimeInterval: 0.25)
            attempts += 1
        }
        XCTFail("Paste editor should accept exported spec content")
    }

    private func tapContinueAndWaitForPreview() {
        let continueButton = sheet.buttons["spec-import-continue-button"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        XCTAssertTrue(continueButton.isEnabled, "Continue should be enabled after pasting spec content")
        continueButton.tap()
        XCTAssertTrue(
            sheet.staticTexts["spec-import-operation-count"].firstMatch.waitForExistence(timeout: 15),
            "Preview operation count should appear after parsing"
        )
    }

    private func accessibilityText(for element: XCUIElement) -> String {
        let label = element.label
        if !label.isEmpty { return label }
        if let value = element.value as? String, !value.isEmpty { return value }
        return ""
    }
}

/// Mirrors `SpecExportAccessibility` IDs without linking the UI test bundle to app internals.
private enum SpecExportAccessibilityID {
    static let sheetExportButton = "spec-export-export-button"
}