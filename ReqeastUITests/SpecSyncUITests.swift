//
//  SpecSyncUITests.swift
//  ReqeastUITests
//

import XCTest

final class SpecSyncUITests: XCTestCase {
    private var app: XCUIApplication!
    private var importSheet: XCUIElement?

    private var sheet: XCUIElement { importSheet ?? app }

    private static let testSpecURL = "https://spec-sync-ui.example.test/petstore.yaml"
    private static let projectName = "Spec Sync UI Test"
    private static let listPetsName = "List all pets"
    private static let getPetByIdName = "Find pet by ID"
    private static let customListName = "My custom list"

    override func setUpWithError() throws {
        continueAfterFailure = false
        launchApp(includeRenameHook: false)
    }

    func testLinkedImportEditNameSyncPreservesName() throws {
        app.terminate()
        launchApp(includeRenameHook: true)
        importLinkedProjectFromURL()
        selectProject(named: Self.projectName)
        waitForRenamedRequest()
        runSyncReviewAndApply()

        let customRequest = UITestHelpers.requestRow(named: Self.customListName, in: app)
        let customLabel = app.staticTexts[Self.customListName].firstMatch
        XCTAssertTrue(
            customRequest.waitForExistence(timeout: 10) || customLabel.waitForExistence(timeout: 3),
            "Sync should preserve user-renamed request name"
        )

        XCTAssertFalse(
            app.staticTexts["List pets from spec"].firstMatch.waitForExistence(timeout: 2),
            "Rule A should not overwrite renamed request with spec summary"
        )
    }

    func testLinkedURLPreviewShowsLinkedDisclaimer() throws {
        openImportSpecSheet()
        selectURLSourceTab()
        waitForURLContent()
        tapFetchAndWaitForPreview(expectedOperationCount: 2)

        let disclaimer = sheet.descendants(matching: .any)["spec-import-url-linked-disclaimer"].firstMatch
        XCTAssertTrue(
            disclaimer.waitForExistence(timeout: 10),
            "URL preview should show linked disclaimer before import"
        )
    }

    func testSyncReviewSummaryShowsModifiedAndRemovedCounts() throws {
        importLinkedProjectFromURL()
        selectProject(named: Self.projectName)
        openSpecLinkPanel()
        tapCheckForUpdates()
        waitForSyncReviewSheet()

        let summary = app.descendants(matching: .any)[SpecSyncAccessibilityID.summaryCounts].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        let summaryText = accessibilityText(for: summary)
        XCTAssertTrue(
            summaryText.contains("1 modified"),
            "Sync review summary should report 1 modified, got: \(summaryText)"
        )
        XCTAssertTrue(
            summaryText.contains("1 removed"),
            "Sync review summary should report 1 removed, got: \(summaryText)"
        )
    }

    func testSyncReviewCancelDismissesWithoutApplyingChanges() throws {
        importLinkedProjectFromURL()
        selectProject(named: Self.projectName)
        openSpecLinkPanel()
        tapCheckForUpdates()
        waitForSyncReviewSheet()
        tapCancelOnReviewSheet()

        XCTAssertFalse(
            app.buttons[SpecSyncAccessibilityID.applyButton].firstMatch.waitForExistence(timeout: 3),
            "Sync review sheet should dismiss after cancel"
        )

        let staleBadge = app.descendants(matching: .any)[SpecSyncAccessibilityID.toolbarBadge].firstMatch
        if staleBadge.waitForExistence(timeout: 3) {
            let badgeState = UITestHelpers.specBadgeAccessibilityState(in: app)
            XCTAssertFalse(
                badgeState.contains("1 stale"),
                "Cancel should not apply sync; badge should not show stale count, got: \(badgeState)"
            )
        }

        let getPetById = UITestHelpers.requestRow(named: Self.getPetByIdName, in: app)
        let getPetByIdLabel = app.staticTexts[Self.getPetByIdName].firstMatch
        XCTAssertTrue(
            getPetById.waitForExistence(timeout: 10) || getPetByIdLabel.waitForExistence(timeout: 3),
            "Find pet by ID request should remain after canceling sync review"
        )
    }

    func testRemovedOpShowsStaleBadgeAndKeepsRequest() throws {
        importLinkedProjectFromURL()
        selectProject(named: Self.projectName)
        runSyncReviewAndApply()

        let staleBadge = app.descendants(matching: .any)[SpecSyncAccessibilityID.toolbarBadge].firstMatch
        XCTAssertTrue(staleBadge.waitForExistence(timeout: 10), "Stale spec badge should appear after sync")

        let badgeState = UITestHelpers.specBadgeAccessibilityState(in: app)
        XCTAssertTrue(
            badgeState.contains("1 stale"),
            "Badge should report one stale request, got: \(badgeState)"
        )

        let removedRequest = UITestHelpers.requestRow(named: Self.getPetByIdName, in: app)
        let removedLabel = app.staticTexts[Self.getPetByIdName].firstMatch
        XCTAssertTrue(
            removedRequest.waitForExistence(timeout: 10) || removedLabel.waitForExistence(timeout: 3),
            "Removed-from-spec operation should remain in the project (not auto-deleted)"
        )
    }

    // MARK: - Import + sync helpers

    private func importLinkedProjectFromURL() {
        openImportSpecSheet()
        selectURLSourceTab()
        waitForURLContent()
        tapFetchAndWaitForPreview(expectedOperationCount: 2)
        tapImportAndWaitForProject()
    }

    private func runSyncReviewAndApply() {
        openSpecLinkPanel()
        tapCheckForUpdates()
        waitForSyncReviewSheet()
        tapApplyOnReviewSheet()
        XCTAssertFalse(
            app.buttons[SpecSyncAccessibilityID.applyButton].firstMatch.waitForExistence(timeout: 3),
            "Sync review sheet should dismiss after apply"
        )
    }

    private func openSpecLinkPanel() {
        let badge = app.descendants(matching: .any)[SpecSyncAccessibilityID.toolbarBadge].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 10), "Spec toolbar badge should be visible for linked project")
        UITestHelpers.assertLinkedSpecBadge(in: app)
        UITestHelpers.press(badge)
        XCTAssertTrue(
            specLinkPanel.waitForExistence(timeout: 10),
            "Spec link panel should open from toolbar badge"
        )
    }

    private var specLinkPanel: XCUIElement {
        app.descendants(matching: .any)[SpecSyncAccessibilityID.specLinkPanel].firstMatch
    }

    private func tapCheckForUpdates() {
        let candidates: [XCUIElement] = [
            specLinkPanel.buttons[SpecSyncAccessibilityID.checkForUpdatesButton].firstMatch,
            specLinkPanel.buttons["Check for updates"].firstMatch,
            app.buttons[SpecSyncAccessibilityID.checkForUpdatesButton].firstMatch,
            app.buttons["Check for updates"].firstMatch,
        ]

        for button in candidates where button.waitForExistence(timeout: 5) {
            XCTAssertTrue(button.isEnabled, "Check for updates should be enabled")
            UITestHelpers.press(button)
            return
        }

        XCTFail("Check for updates button should appear in spec link panel for linked URL import")
    }

    private func waitForSyncReviewSheet() {
        XCTAssertTrue(
            app.staticTexts[SpecSyncAccessibilityID.summaryCounts].firstMatch.waitForExistence(timeout: 15),
            "Sync review sheet should show change summary"
        )
    }

    private func tapApplyOnReviewSheet() {
        let applyButton = app.buttons[SpecSyncAccessibilityID.applyButton].firstMatch
        XCTAssertTrue(applyButton.waitForExistence(timeout: 5))
        XCTAssertTrue(applyButton.isEnabled, "Apply should be enabled with default selections")
        UITestHelpers.press(applyButton)
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func tapCancelOnReviewSheet() {
        let cancelButton = app.buttons[SpecSyncAccessibilityID.cancelButton].firstMatch
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        UITestHelpers.press(cancelButton)
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func waitForRenamedRequest() {
        XCTAssertTrue(
            UITestHelpers.requestRow(named: Self.customListName, in: app).waitForExistence(timeout: 10),
            "UITest rename hook should rename listPets request before sync"
        )
    }

    // MARK: - Import helpers

    private func launchApp(includeRenameHook: Bool) {
        app = XCUIApplication()
        var arguments = ["-screenshotMode", "-specSyncUITest"]
        if includeRenameHook {
            arguments.append("-specSyncUITestRenameOp=listPets")
            arguments.append("-specSyncUITestRenameTo=\(Self.customListName)")
        }
        app.launchArguments = arguments
        app.launch()
        waitForAppReady()
    }

    private func waitForAppReady() {
        UITestHelpers.activateAndWaitForWindow(app)
        let readyMarker = app.buttons["Add"].firstMatch
        let fileMenu = app.menuBars.menuBarItems["File"].firstMatch
        let becameReady = readyMarker.waitForExistence(timeout: 25)
            || fileMenu.waitForExistence(timeout: 5)
        XCTAssertTrue(becameReady, "Reqeast UI should finish launching")
        Thread.sleep(forTimeInterval: 1.0)
    }

    private func openImportSpecSheet() {
        importSheet = UITestHelpers.openImportSpecSheet(in: app)
    }

    private func selectURLSourceTab() {
        let candidates: [XCUIElement] = [
            sheet.buttons["spec-import-source-tab-url"].firstMatch,
            sheet.radioButtons["spec-import-source-tab-url"].firstMatch,
            sheet.buttons["URL"].firstMatch,
            sheet.segmentedControls["spec-import-source-picker"].buttons["URL"].firstMatch,
        ]

        for candidate in candidates where candidate.waitForExistence(timeout: 2) {
            UITestHelpers.press(candidate)
            Thread.sleep(forTimeInterval: 0.3)
            return
        }

        let segmentedControls = sheet.segmentedControls
        if segmentedControls.count > 0 {
            let urlSegment = segmentedControls.element(boundBy: 0).buttons.element(boundBy: 1)
            if urlSegment.waitForExistence(timeout: 3) {
                UITestHelpers.press(urlSegment)
                Thread.sleep(forTimeInterval: 0.3)
                return
            }
        }

        XCTFail("Could not find URL source tab in Import Spec sheet")
    }

    private func waitForURLContent() {
        let fetchButton = sheet.buttons["spec-import-fetch-button"].firstMatch
        var attempts = 0
        while attempts < 20 {
            if fetchButton.exists && fetchButton.isEnabled { return }
            Thread.sleep(forTimeInterval: 0.25)
            attempts += 1
        }
        let urlField = sheet.textFields["spec-import-url-field"].firstMatch
        let value = urlField.exists ? (urlField.value as? String ?? "") : ""
        XCTFail("URL field should be prefilled for sync UITest, got: \(value)")
    }

    private func tapFetchAndWaitForPreview(expectedOperationCount: Int) {
        let fetchButton = sheet.buttons["spec-import-fetch-button"].firstMatch
        XCTAssertTrue(fetchButton.waitForExistence(timeout: 5))
        UITestHelpers.press(fetchButton)

        let opCountElement = sheet.staticTexts["spec-import-operation-count"].firstMatch
        XCTAssertTrue(
            opCountElement.waitForExistence(timeout: 15),
            "Preview should show operation count after fetch"
        )
        let opCountText = accessibilityText(for: opCountElement)
        XCTAssertTrue(
            opCountText.contains("\(expectedOperationCount)"),
            "Expected \(expectedOperationCount) operations in preview, got: \(opCountText)"
        )
    }

    private func tapImportAndWaitForProject() {
        let importButton = sheet.buttons["spec-import-import-button"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        XCTAssertTrue(importButton.isEnabled, "Import should be enabled on preview")
        UITestHelpers.press(importButton)

        XCTAssertFalse(
            app.buttons["spec-import-cancel-button"].firstMatch.waitForExistence(timeout: 10),
            "Import sheet should dismiss after import"
        )

        // Successful import auto-selects the project and shows its request list.
        let listPets = UITestHelpers.requestRow(named: Self.listPetsName, in: app)
        let customList = UITestHelpers.requestRow(named: Self.customListName, in: app)
        let getPetById = UITestHelpers.requestRow(named: Self.getPetByIdName, in: app)
        XCTAssertTrue(
            listPets.waitForExistence(timeout: 15)
                || customList.waitForExistence(timeout: 3)
                || getPetById.waitForExistence(timeout: 3),
            "Imported linked project should show requests after import"
        )

        let backButton = app.buttons["Projects"].firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Projects back button should appear")
        UITestHelpers.press(backButton)
        Thread.sleep(forTimeInterval: 0.5)

        let projectRow = UITestHelpers.projectRow(named: Self.projectName, in: app)
        XCTAssertTrue(
            projectRow.waitForExistence(timeout: 10),
            "Imported linked project should appear in sidebar"
        )
    }

    private func selectProject(named name: String) {
        let projectRow = UITestHelpers.projectRow(named: name, in: app)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 5), "Project \(name) should exist")
        UITestHelpers.press(projectRow)
        Thread.sleep(forTimeInterval: 0.5)
    }

    @discardableResult
    private func selectMenuItem(named name: String) -> Bool {
        let candidates: [XCUIElement] = [
            app.menuItems[name].firstMatch,
            app.menuBars.menuItems[name].firstMatch,
            app.menus.menuItems[name].firstMatch,
            sheet.menuItems[name].firstMatch,
        ]
        for item in candidates where item.waitForExistence(timeout: 2) {
            UITestHelpers.press(item)
            return true
        }
        return false
    }

    private func accessibilityText(for element: XCUIElement) -> String {
        let label = element.label
        if !label.isEmpty { return label }
        if let value = element.value as? String, !value.isEmpty { return value }
        return ""
    }
}

/// Mirrors `SpecSyncAccessibility` IDs without linking the UI test bundle to app internals.
private enum SpecSyncAccessibilityID {
    static let toolbarBadge = "sync-review-toolbar-badge"
    static let specLinkPanel = "sync-review-spec-link-panel"
    static let checkForUpdatesButton = "sync-review-check-for-updates"
    static let summaryCounts = "sync-review-summary-counts"
    static let applyButton = "sync-review-apply-button"
    static let cancelButton = "sync-review-cancel-button"
}