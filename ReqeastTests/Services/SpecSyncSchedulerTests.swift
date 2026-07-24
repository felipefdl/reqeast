//
//  SpecSyncSchedulerTests.swift
//  ReqeastTests
//
//  AC28: background spec check is opt-in, fingerprint-only, and never auto-applies.
//

import Foundation
import Testing
@testable import Reqeast

@Suite("SpecSyncScheduler", .serialized)
struct SpecSyncSchedulerTests {

    @Test @MainActor func eligibleProjectsRequireOptIn() {
        let optedIn = makeLinkedProject(name: "Opted In", backgroundCheckEnabled: true)
        let optedOut = makeLinkedProject(name: "Opted Out", backgroundCheckEnabled: false)
        let store = ProjectStore.mock(projects: [optedIn, optedOut])

        let eligible = SpecSyncService.projectsEligibleForBackgroundCheck(in: store)

        #expect(eligible.count == 1)
        #expect(eligible.first?.id == optedIn.id)
    }

    @Test @MainActor func schedulerDoesNotFetchWithoutOptIn() async {
        SpecSyncSchedulerTestSupport.reset()

        let project = makeLinkedProject(backgroundCheckEnabled: false)
        let store = ProjectStore.mock(projects: [project])
        let scheduler = SpecSyncScheduler.shared
        scheduler.configure(store: store)
        scheduler.postedNotifications = []

        _ = await scheduler.runScheduledChecks()

        #expect(SpecSyncSchedulerTestSupport.totalFetchCount == 0)
        #expect(scheduler.postedNotifications.isEmpty)
    }

    @Test @MainActor func schedulerFetchesOptedInLinkedProject() async {
        SpecSyncSchedulerTestSupport.reset()

        let project = makeLinkedProject(
            backgroundCheckEnabled: true,
            contentFingerprint: "stale-fingerprint"
        )
        let store = ProjectStore.mock(projects: [project])
        let scheduler = SpecSyncScheduler.shared
        scheduler.configure(store: store)
        scheduler.postedNotifications = []

        _ = await scheduler.runScheduledChecks()

        #expect(SpecSyncSchedulerTestSupport.fetchCount(for: project.id) == 1)
    }

    @Test @MainActor func schedulerDoesNotNotifyWhenFingerprintUnchanged() async throws {
        SpecSyncSchedulerTestSupport.reset()

        let projectId = UUID()
        let fixtureBytes = try #require(
            SpecSyncUITestSupport.fetchData(for: URL(string: SpecSyncUITestSupport.testURL)!)
        )
        let fingerprint = canonicalFingerprint(resolvedBytes: fixtureBytes)
        let project = makeLinkedProject(
            id: projectId,
            backgroundCheckEnabled: true,
            contentFingerprint: fingerprint
        )
        let store = ProjectStore.mock(projects: [project])
        let scheduler = SpecSyncScheduler.shared
        scheduler.configure(store: store)
        scheduler.postedNotifications = []

        _ = await scheduler.runScheduledChecks()

        #expect(SpecSyncSchedulerTestSupport.fetchCount(for: projectId) == 1)
        #expect(scheduler.postedNotifications.isEmpty)

        let updated = try #require(store.projects.first(where: { $0.id == projectId }))
        #expect(updated.specLink?.lastCheckedAt != nil)
        #expect(updated.specLink?.contentFingerprint == fingerprint)
    }

    @Test @MainActor func schedulerNotifiesOnFingerprintChangeWithoutApplying() async throws {
        SpecSyncSchedulerTestSupport.reset()

        let projectId = UUID()
        let project = makeLinkedProject(
            id: projectId,
            name: "Petstore",
            backgroundCheckEnabled: true,
            contentFingerprint: "stale-fingerprint"
        )
        let store = ProjectStore.mock(projects: [project])
        let scheduler = SpecSyncScheduler.shared
        scheduler.configure(store: store)
        scheduler.postedNotifications = []

        _ = await scheduler.runScheduledChecks()

        #expect(SpecSyncSchedulerTestSupport.fetchCount(for: projectId) == 1)
        #expect(scheduler.postedNotifications.count == 1)
        #expect(scheduler.postedNotifications.first?.projectId == projectId)
        #expect(scheduler.postedNotifications.first?.projectName == "Petstore")

        let updated = try #require(store.projects.first(where: { $0.id == projectId }))
        #expect(updated.specLink?.lastCheckedAt != nil)
        #expect(updated.specLink?.contentFingerprint == "stale-fingerprint")
        #expect(updated.specLink?.specRevision == 0)
        #expect(store.requests.isEmpty)
    }

    @Test @MainActor func backgroundFingerprintCheckReturnsUpToDateWhenFingerprintMatches() async throws {
        SpecSyncSchedulerTestSupport.reset()

        let fixtureBytes = try #require(SpecSyncUITestSupport.fetchData(for: URL(string: SpecSyncUITestSupport.testURL)!))
        let fingerprint = canonicalFingerprint(resolvedBytes: fixtureBytes)
        let project = makeLinkedProject(
            backgroundCheckEnabled: true,
            contentFingerprint: fingerprint
        )
        let store = ProjectStore.mock(projects: [project])

        let outcome = try await SpecSyncService.backgroundFingerprintCheck(project: project, store: store)

        #expect(outcome == .upToDate)
        #expect(SpecSyncSchedulerTestSupport.fetchCount(for: project.id) == 1)
    }

    @Test @MainActor func refreshSchedulingRegistersWhenOptedInExists() {
        let store = ProjectStore.mock(projects: [
            makeLinkedProject(backgroundCheckEnabled: true),
        ])
        let scheduler = SpecSyncScheduler.shared
        scheduler.configure(store: store)

        scheduler.refreshScheduling()

        #if os(iOS)
        #expect(scheduler.hasPendingBackgroundRefreshForTesting)
        #else
        #expect(scheduler.hasActiveMacOSTimerForTesting)
        #endif
    }

    @Test @MainActor func refreshSchedulingCancelsWhenNoOptedInProjects() {
        let store = ProjectStore.mock(projects: [
            makeLinkedProject(backgroundCheckEnabled: false),
        ])
        let scheduler = SpecSyncScheduler.shared
        scheduler.configure(store: store)

        scheduler.refreshScheduling()

        #if os(iOS)
        #expect(!scheduler.hasPendingBackgroundRefreshForTesting)
        #else
        #expect(!scheduler.hasActiveMacOSTimerForTesting)
        #endif
    }

    // MARK: - Helpers

    private func makeLinkedProject(
        id: UUID = UUID(),
        name: String = "Linked",
        backgroundCheckEnabled: Bool,
        contentFingerprint: String = "initial-fingerprint"
    ) -> Project {
        var project = Project(id: id, name: name)
        project.specLink = SpecLink(
            format: .openapi,
            source: .url,
            contentFingerprint: contentFingerprint,
            importedAt: Date(timeIntervalSinceReferenceDate: 1000),
            sourceURL: SpecSyncUITestSupport.testURL,
            isDetached: false,
            backgroundCheckEnabled: backgroundCheckEnabled
        )
        return project
    }
}