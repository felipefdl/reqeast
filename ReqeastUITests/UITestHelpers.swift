//
//  UITestHelpers.swift
//  ReqeastUITests
//

import XCTest

#if os(macOS)
import AppKit
#endif

enum UITestHelpers {
    static func press(_ element: XCUIElement) {
#if os(macOS)
        element.click()
#else
        if element.isHittable {
            element.tap()
        } else if element.exists {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            element.tap()
        }
#endif
    }

    static func activateAndWaitForWindow(_ app: XCUIApplication, timeout: TimeInterval = 15) {
        app.activate()
        let window = app.windows.firstMatch
        _ = window.waitForExistence(timeout: timeout)
    }

    static func projectRow(named name: String, in app: XCUIApplication) -> XCUIElement {
        let id = "project-\(name)"
        let byIdentifier = app.staticTexts[id].firstMatch
        if byIdentifier.exists { return byIdentifier }
        return app.descendants(matching: .any)[id].firstMatch
    }

    static func requestRow(named name: String, in app: XCUIApplication) -> XCUIElement {
        let id = "request-\(name)"
        let byIdentifier = app.staticTexts[id].firstMatch
        if byIdentifier.exists { return byIdentifier }
        return app.descendants(matching: .any)[id].firstMatch
    }

    static func waitForDemoData(in app: XCUIApplication, projectName: String = "Weather API", timeout: TimeInterval = 20) {
        activateAndWaitForWindow(app)
        let marker = projectRow(named: projectName, in: app)
        XCTAssertTrue(
            marker.waitForExistence(timeout: timeout),
            "Demo project '\(projectName)' should appear in sidebar"
        )
        var attempts = 0
        while !marker.isHittable && attempts < 30 {
            Thread.sleep(forTimeInterval: 0.5)
            attempts += 1
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    static func setPasteboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    /// Paste into a focused field; keyboard events must target the sheet/window that owns the field.
    static func paste(_ string: String, into element: XCUIElement, scope: XCUIElement) {
        setPasteboard(string)
        press(element)
        Thread.sleep(forTimeInterval: 0.2)
        scope.typeKey("v", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
    }

    static func replaceText(in field: XCUIElement, with text: String, scope: XCUIElement) {
        press(field)
        Thread.sleep(forTimeInterval: 0.2)
        scope.typeKey("a", modifierFlags: .command)
        if text.count > 80 {
            paste(text, into: field, scope: scope)
        } else {
            field.typeText(text)
        }
        Thread.sleep(forTimeInterval: 0.3)
    }

    static func specBadgeAccessibilityState(in app: XCUIApplication) -> String {
        let badge = app.descendants(matching: .any)["sync-review-toolbar-badge"].firstMatch
        guard badge.exists else { return "" }
        if let value = badge.value as? String, !value.isEmpty { return value }
        return badge.label
    }

    static func assertLinkedSpecBadge(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let state = specBadgeAccessibilityState(in: app)
        XCTAssertTrue(
            state.localizedCaseInsensitiveContains("linked"),
            "Imported project should be linked to spec, badge state: \(state)",
            file: file,
            line: line
        )
    }

    static func navigateToProjectsSidebarIfNeeded(in app: XCUIApplication) {
        #if os(iOS)
        let backButton = app.buttons["Projects"].firstMatch
        if backButton.waitForExistence(timeout: 2) {
            press(backButton)
            Thread.sleep(forTimeInterval: 0.5)
        }
        #endif
    }

    #if os(iOS)
    static func exportOpenAPIFromProjectContextMenu(named projectName: String, in app: XCUIApplication) {
        let projectRow = projectRow(named: projectName, in: app)
        XCTAssertTrue(projectRow.waitForExistence(timeout: 10), "Project \(projectName) should exist for export")
        projectRow.press(forDuration: 1.0)

        let exportItem = app.buttons["Export as OpenAPI..."].firstMatch
        if !exportItem.waitForExistence(timeout: 3) {
            let menuItem = app.staticTexts["Export as OpenAPI..."].firstMatch
            XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "Export as OpenAPI menu item should exist")
            press(menuItem)
        } else {
            press(exportItem)
        }

        let exportButton = app.buttons["spec-export-export-button"].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 10), "Export sheet should expose export button")
        press(exportButton)

        XCTAssertFalse(
            exportButton.waitForExistence(timeout: 5),
            "Export sheet should dismiss after UITest export"
        )
    }
    #endif

    static func openImportSpecSheet(in app: XCUIApplication) -> XCUIElement {
        #if os(macOS)
        let welcomeImport = app.buttons["welcome-import-spec-button"].firstMatch
        if welcomeImport.waitForExistence(timeout: 2) {
            welcomeImport.click()
        } else {
            let addMenu = app.menuButtons["Add"].firstMatch
            let addButton = app.buttons["Add"].firstMatch
            if addMenu.waitForExistence(timeout: 5) {
                addMenu.click()
            } else {
                XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add menu should exist in sidebar toolbar")
                addButton.click()
            }
            Thread.sleep(forTimeInterval: 0.2)

            let menuItemCandidates: [XCUIElement] = [
                app.menuItems["spec-import-menu"].firstMatch,
                app.buttons["spec-import-menu"].firstMatch,
                app.menuItems["Import Spec..."].firstMatch,
                app.menuBars.menuItems["Import Spec..."].firstMatch,
            ]
            var opened = false
            for item in menuItemCandidates where item.waitForExistence(timeout: 3) {
                item.click()
                opened = true
                break
            }
            if !opened {
                let fileMenu = app.menuBars.menuBarItems["File"].firstMatch
                XCTAssertTrue(fileMenu.waitForExistence(timeout: 5))
                fileMenu.click()
                let importSpecItem = app.menuBars.menuItems["Import Spec..."].firstMatch
                XCTAssertTrue(importSpecItem.waitForExistence(timeout: 5))
                importSpecItem.click()
            }
        }
        #else
        navigateToProjectsSidebarIfNeeded(in: app)
        let addButton = app.buttons["Add"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        let importSpecItem = app.buttons["spec-import-menu"].firstMatch
        XCTAssertTrue(importSpecItem.waitForExistence(timeout: 5))
        importSpecItem.tap()
        #endif

        XCTAssertTrue(
            app.buttons["spec-import-cancel-button"].firstMatch.waitForExistence(timeout: 15),
            "Import Spec sheet should appear"
        )
        let sheetWindow = app.windows.containing(.button, identifier: "spec-import-cancel-button").firstMatch
        return sheetWindow.waitForExistence(timeout: 2) ? sheetWindow : app
    }
}