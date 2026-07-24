//
//  ScreenshotTests.swift
//  ReqeastUITests
//

import XCTest
#if canImport(UIKit)
import UIKit
#endif

/// Marketing screenshot capture for App Store assets. Opt-in only: excluded from
/// `just test-ui` because each case sleeps, launches the app, and writes PNGs.
/// Enable via `just screenshots-capture` or `just test-ui-screenshots` (`RUN_SCREENSHOT_TESTS`).
private enum ScreenshotTestGate {
    #if RUN_SCREENSHOT_TESTS
    static let enabled = true
    #else
    static let enabled = false
    #endif
}

final class ScreenshotTests: XCTestCase {
    private var outputDir = ""
    private var lang = "en"
    /// mac | iphone | ipad — resolved in loadConfig (env / config file / screen geometry).
    private var platform = "mac"

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ScreenshotTestGate.enabled,
            "Screenshot tests are opt-in. Run `just screenshots-capture` or `just test-ui-screenshots`."
        )
        continueAfterFailure = false
        loadConfig()
    }

    // MARK: - Screenshots

    func test01_ProjectSidebar() throws {
        #if os(iOS)
        let phone = UIDevice.current.userInterfaceIdiom == .phone
        if phone {
            let app = launchApp(mode: "-screenshotEmpty")
            waitForUI(app)
            saveScreenshot(app, name: "01_ProjectSidebar")
        } else {
            let app = launchApp(mode: "-screenshotMode")
            waitForUI(app)
            waitForDemoData(app)
            // Settle for list paint. a11y can report rows before the sidebar pixels paint
            // (empty white column while Weather is "hittable"). Avoid navigate-and-back.
            let row = app.staticTexts["project-Weather API"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), "Weather API row for sidebar layout")
            XCTAssertTrue(row.isHittable, "Weather API row must be visible for marketing frame")
            // Extra settle: 11" multi plate was empty at ~1–3s; 8s matches prior simctl path.
            Thread.sleep(forTimeInterval: 8.0)
            forceIPadLandscapeIfNeeded()
            dismissSystemChromeTips()
            saveScreenshot(app, name: "01_ProjectSidebar")
        }
        #else
        let app = launchApp()
        waitForUI(app)
        waitForDemoData(app)
        saveScreenshot(app, name: "01_ProjectSidebar")
        #endif
    }

    func test02_HttpRequest() throws {
        let app = launchApp()
        waitForUI(app)

        let projectRow = app.staticTexts["project-Weather API"].firstMatch
        if projectRow.waitForExistence(timeout: 5) {
            projectRow.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }

        let requestRow = app.staticTexts["request-GET Current Weather"].firstMatch
        if requestRow.waitForExistence(timeout: 5) {
            requestRow.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }

        saveScreenshot(app, name: "02_HttpRequest")
    }

    func test03_ProtocolMenu() throws {
        let app = launchApp()
        waitForUI(app)

        #if os(macOS)
        let projectName = "Chat Platform"
        #else
        let projectName = "Weather API"
        #endif

        let projectRow = app.staticTexts["project-\(projectName)"].firstMatch
        if projectRow.waitForExistence(timeout: 5) {
            projectRow.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }

        let menuButton = app.menuButtons["add-request-menu"].firstMatch
        let button = app.buttons["add-request-menu"].firstMatch

        if menuButton.waitForExistence(timeout: 3) {
            menuButton.tap()
        } else if button.waitForExistence(timeout: 3) {
            button.tap()
        }
        Thread.sleep(forTimeInterval: 0.5)

        saveScreenshot(app, name: "03_ProtocolMenu")
    }

    func test04_SocketView() throws {
        let app = launchApp()
        waitForUI(app)

        let projectRow = app.staticTexts["project-IoT Gateway"].firstMatch
        if projectRow.waitForExistence(timeout: 5) {
            projectRow.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }

        let requestRow = app.staticTexts["request-TCP Telemetry Stream"].firstMatch
        if requestRow.waitForExistence(timeout: 5) {
            requestRow.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }

        saveScreenshot(app, name: "04_SocketView")
    }

    // MARK: - Helpers

    private var appleLocale = "en_US"

    #if os(iOS)
    /// `ipad` = 13" standalone marketing; `ipad11` = multi-device collage plate.
    private var isIPadTarget: Bool { platform == "ipad" || platform == "ipad11" }
    #endif

    private func loadConfig() {
        let tmpDir = FileManager.default.temporaryDirectory
        var localeFromEnvOrFile = false
        var platformFromEnvOrFile = false

        // 1) Env from capture script / xcodebuild (inherited by runner when set)
        if let envLang = ProcessInfo.processInfo.environment["SCREENSHOT_LANG"], !envLang.isEmpty {
            lang = envLang.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let envLocale = ProcessInfo.processInfo.environment["SCREENSHOT_APPLE_LOCALE"], !envLocale.isEmpty {
            appleLocale = envLocale.trimmingCharacters(in: .whitespacesAndNewlines)
            localeFromEnvOrFile = true
        }
        if let envPlatform = ProcessInfo.processInfo.environment["SCREENSHOT_PLATFORM"],
           envPlatform == "mac" || envPlatform == "iphone" || envPlatform == "ipad"
            || envPlatform == "ipad11" {
            platform = envPlatform
            platformFromEnvOrFile = true
        }

        // 2) Absolute config written by capture-screenshots.sh (sandbox-readable).
        //    UITest runner temporaryDirectory is the container tmp, not the shell $TMPDIR.
        let configCandidates: [URL] = [
            URL(fileURLWithPath: "/tmp/reqeast-screenshot-config"),
            tmpDir.appendingPathComponent("reqeast-screenshot-config"),
        ]
        for configUrl in configCandidates {
            guard let data = try? Data(contentsOf: configUrl),
                  let content = String(data: data, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                if key == "lang", !value.isEmpty { lang = value }
                if key == "appleLocale", !value.isEmpty {
                    appleLocale = value
                    localeFromEnvOrFile = true
                }
                if key == "platform",
                   value == "mac" || value == "iphone" || value == "ipad" || value == "ipad11" {
                    platform = value
                    platformFromEnvOrFile = true
                }
            }
            break
        }

        // 3) Derive AppleLocale from lang when not provided
        if !localeFromEnvOrFile {
            appleLocale = Self.appleLocale(for: lang)
        }

        // 4) Platform fallback when capture script did not set it
        if !platformFromEnvOrFile {
            #if os(macOS)
            platform = "mac"
            #else
            // UIDevice.idiom in the runner can mis-report phone on iPad destinations.
            let shortSide = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
            if shortSide >= 700 || UIDevice.current.userInterfaceIdiom == .pad {
                platform = "ipad"
            } else {
                platform = "iphone"
            }
            #endif
        }

        // Per-device subdir so mac screencapture never overwrites simulator frames
        // when capture-screenshots.sh prefers container PNGs.
        outputDir = tmpDir
            .appendingPathComponent("reqeast-screenshots/latest/\(platform)")
            .path

        NSLog("ScreenshotTests config lang=\(lang) appleLocale=\(appleLocale) platform=\(platform)")
    }

    private static func appleLocale(for lang: String) -> String {
        switch lang {
        case "en": return "en_US"
        case "zh-Hans": return "zh_CN"
        case "zh-Hant": return "zh_TW"
        case "ja": return "ja_JP"
        case "fr": return "fr_FR"
        case "pt-BR": return "pt_BR"
        case "es": return "es_ES"
        case "ko": return "ko_KR"
        case "de": return "de_DE"
        default: return lang.replacingOccurrences(of: "-", with: "_")
        }
    }

    private func launchApp(mode: String = "-screenshotMode") -> XCUIApplication {
        #if os(iOS)
        forceIPadLandscapeIfNeeded()
        #endif

        let app = XCUIApplication()
        // Prefer language list + matching locale. Format must be the array string Apple expects.
        app.launchArguments = [
            mode,
            "-AppleLanguages", "(\(lang))",
            "-AppleLocale", appleLocale,
            "-NSForceRightToLeftWritingDirection", "NO",
        ]
        // Also seed process environment for frameworks that read AppleLanguages from env.
        app.launchEnvironment["APPLE_LANGUAGES"] = lang
        app.launchEnvironment["LC_ALL"] = appleLocale
        app.launch()
        // Order the app front immediately after launch so WindowGroup creates a
        // visible window (required on macOS for screenshot capture and XCTest queries).
        app.activate()

        #if os(iOS)
        forceIPadLandscapeIfNeeded()
        #endif

        return app
    }

    #if os(iOS)
    /// Marketing iPad bezels are landscape. Multitasking iPad often ignores a single
    /// orientation write; retry until the device reports landscape (or timeout).
    private func forceIPadLandscapeIfNeeded() {
        guard isIPadTarget else { return }
        let device = XCUIDevice.shared
        for _ in 0..<20 {
            if device.orientation == .landscapeLeft || device.orientation == .landscapeRight {
                return
            }
            device.orientation = .landscapeLeft
            Thread.sleep(forTimeInterval: 0.15)
        }
        // Last attempt; saveScreenshot still validates pixel geometry.
        device.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 0.5)
    }
    #endif

    private func waitForUI(_ app: XCUIApplication) {
        // macOS UI tests launch the app without ordering a window front. Without
        // activate(), XCTest never sees a window and the app never appears on screen.
        UITestHelpers.activateAndWaitForWindow(app, timeout: 15)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, "Main window should exist after activate")
        // Let WindowGroup + toolbar settle (same chrome as normal open -a).
        Thread.sleep(forTimeInterval: 2.0)
        #if os(iOS)
        dismissSystemChromeTips()
        #endif
    }

    private func waitForDemoData(_ app: XCUIApplication) {
        UITestHelpers.waitForDemoData(in: app, timeout: 20)
    }

    #if os(iOS)
    /// Simulator chrome promos (e.g. "Ready for Apple Intelligence" CFU banner) ruin marketing frames.
    /// Capture script clears CFU defaults; this is the last-resort swipe/tap before save.
    private func dismissSystemChromeTips() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // Prefer SpringBoard only — scanning the app a11y tree for "intelligence" is slow
        // and can disturb the UI under test.
        let predicate = NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
            "Apple Intelligence",
            "personal intelligence",
            "Ready for Apple"
        )
        for _ in 0..<3 {
            let tip = springboard.descendants(matching: .any).matching(predicate).firstMatch
            guard tip.waitForExistence(timeout: 0.4) else { return }
            if tip.buttons["Close"].exists {
                tip.buttons["Close"].tap()
            } else if tip.buttons.firstMatch.exists, tip.buttons.firstMatch.isHittable {
                tip.buttons.firstMatch.tap()
            } else if tip.isHittable {
                // CFU is a Dynamic Island / status-bar banner: swipe up dismisses.
                tip.swipeUp()
                Thread.sleep(forTimeInterval: 0.15)
                if tip.exists, tip.isHittable {
                    tip.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
                }
            } else {
                // Banner may not report hittable; swipe near top-center of the screen.
                let frame = springboard.frame
                if frame.width > 0, frame.height > 0 {
                    let start = springboard.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)
                    )
                    let end = springboard.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.0)
                    )
                    start.press(forDuration: 0.05, thenDragTo: end)
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }
    #endif

    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        // outputDir already includes platform (mac|iphone|ipad|ipad11) from loadConfig
        let dir = "\(outputDir)/\(lang)"
        let path = "\(dir)/\(name).png"

        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        #if os(macOS)
        // Use screencapture -l to capture with transparent rounded corners
        if let windowId = findWindowId(for: "Reqeast") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-l", String(windowId), "-o", path]
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                NSLog("Screenshot saved (screencapture): \(path)")
            }
        } else {
            // Fallback to XCTest screenshot
            let screenshot = app.windows.firstMatch.screenshot()
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path))
            NSLog("Screenshot saved (fallback): \(path)")
        }
        #else
        forceIPadLandscapeIfNeeded()
        dismissSystemChromeTips()
        let screenshot = XCUIScreen.main.screenshot()
        var png = screenshot.pngRepresentation
        // Simulator framebuffer stays portrait (e.g. 2064×2752) even when the interface
        // is landscape: content is sideways in the PNG. Rotate CW 270° so marketing
        // landscape bezels get upright wide frames (e.g. 2752×2064 / 2420×1668).
        if isIPadTarget, let (w, h) = pngPixelSize(png), h > w {
            if let rotated = rotatePNGClockwise270(png) {
                png = rotated
            }
        }
        try? png.write(to: URL(fileURLWithPath: path))
        NSLog("Screenshot saved: \(path)")
        if isIPadTarget,
           let (w, h) = pngPixelSize(png),
           h > w {
            XCTFail("iPad screenshot \(name) is still portrait \(w)x\(h) after landscape fix")
        }
        #endif

        // Also save as test attachment (use file on disk so attachment matches rotated PNG)
        #if os(iOS)
        if let diskData = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            let attachment = XCTAttachment(data: diskData, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        } else {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        #else
        let attachmentScreenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: attachmentScreenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        #endif
    }

    #if os(iOS)
    private func pngPixelSize(_ data: Data) -> (Int, Int)? {
        guard data.count >= 24 else { return nil }
        // PNG IHDR: 8 sig + 4 len + 4 "IHDR" + 4 width + 4 height
        let w = data.subdata(in: 16..<20).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let h = data.subdata(in: 20..<24).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        return (Int(w), Int(h))
    }

    /// Match `sips -r 270`: portrait buffer with landscape UI → upright landscape PNG.
    private func rotatePNGClockwise270(_ data: Data) -> Data? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        let srcW = cgImage.width
        let srcH = cgImage.height
        let dstW = srcH
        let dstH = srcW
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        // CW 270° in CG (origin bottom-left): translate to right edge, rotate +90° CCW in CTM space
        // yields the same pixels as `sips -r 270` (verified against landscapeLeft captures).
        ctx.translateBy(x: CGFloat(dstW), y: 0)
        ctx.rotate(by: .pi / 2)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))
        guard let outImage = ctx.makeImage() else { return nil }
        return UIImage(cgImage: outImage).pngData()
    }
    #endif

    #if os(macOS)
    private func findWindowId(for appName: String) -> UInt32? {
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        // Prefer the largest on-screen layer-0 window owned by the app.
        // Prefer windows with a non-empty name (real WindowGroup). Untitled surfaces are
        // often the AppKit NSHostingView fallback, which has wrong title-bar chrome.
        var bestNamed: (UInt32, CGFloat)?
        var bestAny: (UInt32, CGFloat)?
        for window in windowList {
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  owner == appName,
                  let windowId = window[kCGWindowNumber as String] as? UInt32,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }
            let area = (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
            guard area > 200_000 else { continue }
            let name = (window[kCGWindowName as String] as? String) ?? ""
            if !name.isEmpty {
                if bestNamed == nil || area > bestNamed!.1 {
                    bestNamed = (windowId, area)
                }
            }
            if bestAny == nil || area > bestAny!.1 {
                bestAny = (windowId, area)
            }
        }
        return bestNamed?.0 ?? bestAny?.0
    }
    #endif
}
