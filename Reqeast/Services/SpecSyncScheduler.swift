//
//  SpecSyncScheduler.swift
//  Reqeast
//
//  Opt-in background linked-spec fingerprint checks (AC28). iOS uses BGAppRefreshTask;
//  macOS uses an NSTimer while the app is running (including across app nap).
//  Check only — never auto-applies; posts a local notification when the fingerprint differs.
//

import Foundation
import Network
import os
import UserNotifications

#if os(iOS)
import BackgroundTasks
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

private let schedulerLogger = Logger(subsystem: "app.reqeast", category: "SpecSyncScheduler")

@MainActor
final class SpecSyncScheduler {
    static let shared = SpecSyncScheduler()
    static let taskIdentifier = "app.reqeast.spec-background-check"

    private static let checkInterval: TimeInterval = 6 * 60 * 60

    private weak var store: ProjectStore?
    private var macOSTimer: Timer?
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "app.reqeast.spec-sync-scheduler.network")
    private var isNetworkAvailable = true

    #if DEBUG
    var postedNotifications: [(projectName: String, projectId: UUID)] = []
    private(set) var hasPendingBackgroundRefreshForTesting = false
    var hasActiveMacOSTimerForTesting: Bool { macOSTimer != nil }
    #endif

    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    func configure(store: ProjectStore) {
        self.store = store
    }

    func start() {
        #if os(iOS)
        registerBackgroundTaskIfNeeded()
        #endif
        refreshScheduling()
    }

    /// Call when opt-in changes or projects are added/removed.
    func refreshScheduling() {
        #if os(iOS)
        registerBackgroundTaskIfNeeded()
        scheduleNextBackgroundRefresh()
        #endif
        refreshMacOSTimer()
    }

    @discardableResult
    func runScheduledChecks() async -> Bool {
        guard let store else { return false }
        guard shouldRunChecks else { return true }

        let projects = SpecSyncService.projectsEligibleForBackgroundCheck(in: store)
        guard !projects.isEmpty else { return true }

        var anyFailure = false
        for project in projects {
            do {
                let outcome = try await SpecSyncService.backgroundFingerprintCheck(
                    project: project,
                    store: store
                )
                if case .updateAvailable = outcome {
                    await postUpdateNotification(projectName: project.name, projectId: project.id)
                }
            } catch {
                schedulerLogger.warning("Background spec check failed for \(project.id): \(error)")
                anyFailure = true
            }
        }

        return !anyFailure
    }

    func requestNotificationAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    // MARK: - iOS background refresh

    #if os(iOS)
    private var isBackgroundTaskRegistered = false

    private func registerBackgroundTaskIfNeeded() {
        guard !isBackgroundTaskRegistered else { return }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await self.handleBackgroundRefresh(refreshTask)
            }
        }
        isBackgroundTaskRegistered = true
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) async {
        scheduleNextBackgroundRefresh()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        let success = await runScheduledChecks()
        task.setTaskCompleted(success: success)
    }

    private func scheduleNextBackgroundRefresh() {
        guard hasOptedInProjects else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
            #if DEBUG
            hasPendingBackgroundRefreshForTesting = false
            #endif
            return
        }

        #if DEBUG
        if StorageEnvironment.isRunningTests {
            hasPendingBackgroundRefreshForTesting = true
            return
        }
        #endif

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.checkInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
            schedulerLogger.debug("Scheduled next background spec check")
            #if DEBUG
            hasPendingBackgroundRefreshForTesting = true
            #endif
        } catch {
            schedulerLogger.error("Failed to schedule background spec check: \(error)")
            #if DEBUG
            hasPendingBackgroundRefreshForTesting = false
            #endif
        }
    }
    #endif

    // MARK: - macOS timer

    private func refreshMacOSTimer() {
        #if os(macOS)
        macOSTimer?.invalidate()
        macOSTimer = nil
        guard hasOptedInProjects else { return }

        let timer = Timer(
            timeInterval: Self.checkInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.runScheduledChecks()
            }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        macOSTimer = timer
        #endif
    }

    // MARK: - Notifications

    private func postUpdateNotification(projectName: String, projectId: UUID) async {
        #if DEBUG
        if SpecSyncSchedulerTestSupport.isEnabled {
            postedNotifications.append((projectName: projectName, projectId: projectId))
            return
        }
        #endif

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Spec updates available")
        content.body = String(
            localized: "\(projectName) has spec changes. Open Reqeast to review and apply them."
        )
        content.sound = .default
        content.userInfo = ["projectId": projectId.uuidString]

        let request = UNNotificationRequest(
            identifier: "spec-update-\(projectId.uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            schedulerLogger.error("Failed to post spec update notification: \(error)")
        }
    }

    // MARK: - Guards

    private var hasOptedInProjects: Bool {
        guard let store else { return false }
        return !SpecSyncService.projectsEligibleForBackgroundCheck(in: store).isEmpty
    }

    private var shouldRunChecks: Bool {
        #if os(iOS)
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            schedulerLogger.debug("Skipping background spec check: Low Power Mode")
            return false
        }
        #endif
        guard isNetworkAvailable else {
            schedulerLogger.debug("Skipping background spec check: offline")
            return false
        }
        return true
    }
}