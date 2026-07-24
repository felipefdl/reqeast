//
//  StorageEnvironment.swift
//  Reqeast
//

import Foundation

enum StorageEnvironment {
    /// Computed (not `static let`) so launch args from UITest are always visible — cached
    /// `static let` can theoretically run before args are attached in some host setups.
    static var isScreenshotMode: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-screenshotMode")
            || args.contains("-screenshotEmpty")
            || args.contains("-screenshotReload")
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var keyPrefix: String {
        #if DEBUG
        // Marketing capture must never use debug. (real project list).
        if isScreenshotMode { return "screenshot." }
        if isRunningTests { return "test." }
        return "debug."
        #else
        return ""
        #endif
    }

    static var sessionsDirName: String {
        #if DEBUG
        if isScreenshotMode { return "sessions-screenshot" }
        if isRunningTests { return "sessions-test" }
        return "sessions-debug"
        #else
        return "sessions"
        #endif
    }

    static var specsDirName: String {
        #if DEBUG
        if isScreenshotMode { return "specs-screenshot" }
        if isRunningTests { return "specs-test" }
        return "specs-debug"
        #else
        return "specs"
        #endif
    }

    static var mcpDirName: String {
        #if DEBUG
        if isScreenshotMode { return "mcp-screenshot" }
        if isRunningTests { return "mcp-test" }
        return "mcp-debug"
        #else
        return "mcp"
        #endif
    }

    /// CloudKit per-record system-field cache (replaces monolithic UserDefaults blob).
    static var syncCacheDirName: String {
        #if DEBUG
        if isScreenshotMode { return "sync-cache-screenshot" }
        if isRunningTests { return "sync-cache-test" }
        return "sync-cache-debug"
        #else
        return "sync-cache"
        #endif
    }

    /// Project library blobs (requests) — too large for UserDefaults on big spec imports.
    static var libraryDirName: String {
        #if DEBUG
        if isScreenshotMode { return "library-screenshot" }
        if isRunningTests { return "library-test" }
        return "library-debug"
        #else
        return "library"
        #endif
    }

    static var protoDirName: String {
        #if DEBUG
        if isScreenshotMode { return "protos-screenshot" }
        if isRunningTests { return "protos-test" }
        return "protos-debug"
        #else
        return "protos"
        #endif
    }
}
