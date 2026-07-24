//
//  ReqeastApp.swift
//  Reqeast
//

import AppIntents
import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(macOS)
private let mainTabbingId = "com.reqeast.main"

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObserver: NSObjectProtocol?
    /// Retains a host window when SwiftUI WindowGroup fails to present (CLI / some UITest hosts).
    private var fallbackMainWindow: NSWindow?

    /// True when launched for marketing screenshots or UITests (UITest runner injects `-screenshotMode`).
    private var isScreenshotOrUITestLaunch: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-screenshotMode")
            || args.contains("-screenshotEmpty")
            || args.contains("-screenshotReload")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // UITests / screenshot capture need a window every launch. Returning false lets the
        // process sit in the menu bar with zero windows after a closed/restored empty state.
        if isScreenshotOrUITestLaunch { return true }
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Returning true with no visible windows asks the system to open a new WindowGroup scene.
        if !flag {
            bringMainWindowsForward()
            ensureFallbackMainWindowIfNeeded()
        }
        return true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        if isScreenshotOrUITestLaunch {
            // Avoid restored "no windows" state and tab-into-nothing behavior under UI tests.
            WindowTabbingState.preferTabs = false
            WindowTabbingState.pendingTabTarget = nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleNewWindow(notification)
        }

        configureExistingMainWindows()
        // SwiftUI may attach the first WindowGroup after didFinishLaunching. Bring it
        // forward once immediately and again on the next turn of the run loop.
        bringMainWindowsForward()
        DispatchQueue.main.async { [weak self] in
            self?.bringMainWindowsForward()
        }
        // CLI / xcodebuild UITest hosts often never present WindowGroup (menu bar only).
        // Wait longer before AppKit fallback — fallback NSHostingView chrome looks wrong
        // for marketing (weird title bar + sidebar vs real WindowGroup / references/mac-1).
        let fallbackDelay: TimeInterval = isScreenshotOrUITestLaunch ? 3.0 : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + fallbackDelay) { [weak self] in
            self?.ensureFallbackMainWindowIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        ProjectStore.shared.saveLocal()
    }

    private func configureExistingMainWindows() {
        for window in NSApplication.shared.windows where isMainWindow(window) {
            window.tabbingIdentifier = mainTabbingId
            window.tabbingMode = .preferred
        }
    }

    private func bringMainWindowsForward() {
        let mains = NSApplication.shared.windows.filter { isMainWindow($0) || $0 === fallbackMainWindow }
        for window in mains {
            window.isRestorable = !isScreenshotOrUITestLaunch
            if isScreenshotOrUITestLaunch {
                applyMarketingScreenshotWindowChrome(to: window)
            }
            window.makeKeyAndOrderFront(nil)
        }
        if !mains.isEmpty || isScreenshotOrUITestLaunch {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// No-op for chrome. Screenshot captures must look exactly like a normal `open -a`
    /// window. Any titleVisibility / toolbarStyle / title mutation changes the menu bar
    /// and is what made Mac marketing shots look “weird” vs the real app and
    /// `screenshots/references/mac-1.png`.
    private func applyMarketingScreenshotWindowChrome(to window: NSWindow) {
        // Intentionally empty — do not touch title bar, toolbar, or size.
        _ = window
    }

    /// When SwiftUI never materializes a WindowGroup scene (common under CLI launch), host
    /// ContentView in an AppKit window so screenshots / UITests still have a UI surface.
    private func ensureFallbackMainWindowIfNeeded() {
        let hasVisibleMain = NSApplication.shared.windows.contains { window in
            (isMainWindow(window) || window === fallbackMainWindow) && window.isVisible
        }
        guard !hasVisibleMain else {
            bringMainWindowsForward()
            return
        }

        if let existing = fallbackMainWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Match marketing MacBook Display aspect (~1.54). Tall/narrow windows make the
        // project sidebar look sparse and wrong in App Store screenshots.
        let fallbackSize = NSSize(width: 1100, height: 800)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fallbackSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("main-fallback")
        window.tabbingIdentifier = mainTabbingId
        window.tabbingMode = .preferred
        window.isRestorable = false
        // Host SwiftUI with a root that can install a toolbar into this NSWindow.
        let hosting = NSHostingView(rootView: ContentView())
        window.contentView = hosting
        window.setFrameAutosaveName("")
        if isScreenshotOrUITestLaunch {
            applyMarketingScreenshotWindowChrome(to: window)
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        fallbackMainWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleNewWindow(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              isMainWindow(window) else { return }

        // Prefer the real SwiftUI scene; drop the AppKit fallback if it was used.
        if let fallback = fallbackMainWindow, fallback !== window {
            fallback.orderOut(nil)
            fallbackMainWindow = nil
        }

        window.tabbingIdentifier = mainTabbingId
        window.tabbingMode = .preferred
        if isScreenshotOrUITestLaunch {
            applyMarketingScreenshotWindowChrome(to: window)
        }

        guard WindowTabbingState.preferTabs,
              let target = WindowTabbingState.pendingTabTarget,
              target !== window,
              target.isVisible else {
            WindowTabbingState.pendingTabTarget = nil
            window.makeKeyAndOrderFront(nil)
            return
        }

        WindowTabbingState.pendingTabTarget = nil
        target.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    }

    private func isMainWindow(_ window: NSWindow) -> Bool {
        // Never treat the AppKit marketing/UITest fallback as the real main scene.
        // Its NSHostingView chrome does not match WindowGroup (references/mac-1.png).
        if window === fallbackMainWindow { return false }
        guard let identifier = window.identifier?.rawValue else { return false }
        if identifier == "main-fallback" { return false }
        return identifier.contains("main")
    }
}
#endif

#if os(iOS)
/// Locks iPad to landscape during marketing screenshot capture. Multitasking iPad apps
/// ignore `XCUIDevice.orientation` alone; bezels in Pixelmator templates are landscape.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if StorageEnvironment.isScreenshotMode, UIDevice.current.userInterfaceIdiom == .pad {
            return .landscape
        }
        return .all
    }
}
#endif

@main
struct ReqeastApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    #endif
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        ReqeastShortcuts.updateAppShortcutParameters()
        // DO NOT REMOVE. CKSyncEngine requires the Remote Notifications entitlement
        // and expects the app to register for remote notifications. The engine
        // creates its own CKDatabaseSubscription and handles silent pushes
        // internally, so we do NOT need a didReceiveRemoteNotification handler.
        // Removing this (or the `remote-notification` UIBackgroundMode in
        // Info.plist) breaks iCloud sync entirely. See CLAUDE.md > iCloud Sync.
        #if os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #else
        UIApplication.shared.registerForRemoteNotifications()
        #endif
        // Touch ProjectStore so CloudSyncService.start() runs during App.init()
        // rather than lazily on first view build. Needed for background launches
        // triggered by CloudKit silent pushes: if the engine isn't alive when the
        // push arrives, the sync opportunity is lost. DO NOT REMOVE.
        _ = ProjectStore.shared
        Task { @MainActor in
            SpecSyncScheduler.shared.configure(store: ProjectStore.shared)
            SpecSyncScheduler.shared.start()
        }
        // Warm up HttpService on a background thread at launch.
        // HttpClient() creates a tokio multi-threaded runtime which takes ~1-3s on iOS.
        // Without this, the runtime is created lazily on the main thread when the user
        // first selects a request, freezing the UI.
        Task.detached(priority: .userInitiated) {
            await HttpService.warmUp()
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-screenshotMode") {
            // Load synchronously so UITests and screenshot capture see demo data on first frame.
            _ = DemoDataService.load(into: .shared)
        } else if ProcessInfo.processInfo.arguments.contains("-screenshotEmpty") {
            ProjectStore.shared.resetAllData()
        }
        #endif
        #if os(iOS)
        Self.requestIPadScreenshotLandscapeIfNeeded()
        #endif
    }

    #if os(iOS)
    /// Ask scenes to adopt landscape so marketing iPad frames get wide content, not stretched portrait.
    private static func requestIPadScreenshotLandscapeIfNeeded() {
        guard StorageEnvironment.isScreenshotMode, UIDevice.current.userInterfaceIdiom == .pad else { return }
        let apply: () -> Void = {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
            }
        }
        // Scenes may not exist yet during App.init; retry once on the next run-loop turn.
        DispatchQueue.main.async(execute: apply)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: apply)
    }
    #endif

    var body: some Scene {
        mainWindow

        #if os(macOS)
        Settings {
            SettingsView()
        }

        Window("Open Source Licenses", id: "licenses") {
            LicensesSettingsView()
        }
        .defaultSize(width: 500, height: 500)


        #endif
    }

    private var mainWindow: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        #if os(macOS)
        // Always present a window on launch. Without this, UITest / screenshot launches can
        // restore an empty session: menu bar present, zero windows (process stays alive
        // because applicationShouldTerminateAfterLastWindowClosed is false in normal use).
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1100, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            ReqeastCommands(openWindow: openWindow)
        }
        #endif
    }
}
