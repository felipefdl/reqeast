//
//  SpecImportPerformanceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

// MARK: - Performance harness

private enum SpecImportPerformanceSLO {
    static let sampleCount = 20
    static let warmupCount = 3
    static let p95LimitSeconds = 5.0
    static let mainThreadHangLimitMs = 100.0
    static let regressionTolerance = 1.20
}

private struct SpecImportPerformanceBaseline: Codable {
    var fixture: String
    var metric: String
    var p95Seconds: Double
    var sampleCount: Int
    var recordedAt: String
    var platform: String

    enum CodingKeys: String, CodingKey {
        case fixture
        case metric
        case p95Seconds = "p95_seconds"
        case sampleCount = "sample_count"
        case recordedAt = "recorded_at"
        case platform
    }
}

private extension Duration {
    var secondsDouble: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1_000_000_000_000_000_000
    }
}

private func percentile(_ values: [Duration], _ percentile: Double) -> Duration {
    precondition(!values.isEmpty)
    let sorted = values.sorted { $0 < $1 }
    let rank = Int(ceil(percentile * Double(sorted.count))) - 1
    return sorted[min(max(rank, 0), sorted.count - 1)]
}

/// Polls main-thread responsiveness while spec import work runs.
private final class MainThreadHangMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var _maxObservedMs = 0.0

    var maxObservedMs: Double {
        lock.lock()
        defer { lock.unlock() }
        return _maxObservedMs
    }

    func start() {
        let queue = DispatchQueue(label: "spec-import.main-thread-hang-monitor", qos: .userInteractive)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let observedMs = self.probeMainThreadResponseMs()
            self.lock.lock()
            self._maxObservedMs = max(self._maxObservedMs, observedMs)
            self.lock.unlock()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func probeMainThreadResponseMs() -> Double {
        let semaphore = DispatchSemaphore(value: 0)
        let start = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async {
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 0.25)
        return (CFAbsoluteTimeGetCurrent() - start) * 1_000
    }
}

// MARK: - Tests

/// Opt-in gate (T21): excluded from `just test-all` because parallel suites delay
/// main-thread hang probes (~155 ms false positives vs 100 ms SLO). Enable via
/// `just test-spec-perf`, which compiles with `RUN_SPEC_PERF`.
#if RUN_SPEC_PERF
private let shouldRunSpecImportPerformanceGate = true
#else
private let shouldRunSpecImportPerformanceGate = false
#endif

@Suite("SpecImportPerformance", .serialized, .enabled(if: shouldRunSpecImportPerformanceGate))
struct SpecImportPerformanceTests {

    static let fixturesDirectory: URL = {
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            return URL(fileURLWithPath: srcRoot, isDirectory: true)
                .appendingPathComponent("ReqeastTests/Fixtures/SpecImport", isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SpecImport", isDirectory: true)
    }()

    @Test(
        "stress-500 preview parse+map meets AC4 performance SLO",
        .timeLimit(.minutes(3))
    )
    @MainActor
    func stress500PreviewMeetsPerformanceSLO() async throws {
        let bytes = try fixtureBytes(named: "stress-500")
        let hangMonitor = MainThreadHangMonitor()
        hangMonitor.start()
        defer { hangMonitor.stop() }

        for _ in 0..<SpecImportPerformanceSLO.warmupCount {
            _ = try await previewStress500(bytes: bytes)
        }

        var samples: [Duration] = []
        samples.reserveCapacity(SpecImportPerformanceSLO.sampleCount)

        for _ in 0..<SpecImportPerformanceSLO.sampleCount {
            let start = ContinuousClock.now
            _ = try await previewStress500(bytes: bytes)
            samples.append(start.duration(to: ContinuousClock.now))
        }

        let p95 = percentile(samples, 0.95)
        let p95Seconds = p95.secondsDouble
        #expect(
            p95Seconds < SpecImportPerformanceSLO.p95LimitSeconds,
            "stress-500 preview p95 \(p95Seconds)s exceeded \(SpecImportPerformanceSLO.p95LimitSeconds)s SLO"
        )

        if let baseline = try loadBaseline(named: "stress-500") {
            let regressionLimit = baseline.p95Seconds * SpecImportPerformanceSLO.regressionTolerance
            #expect(
                p95Seconds <= regressionLimit,
                "stress-500 preview p95 \(p95Seconds)s regressed beyond \(regressionLimit)s (baseline \(baseline.p95Seconds)s + 20%)"
            )
        }

        #expect(
            hangMonitor.maxObservedMs <= SpecImportPerformanceSLO.mainThreadHangLimitMs,
            "main thread was unresponsive for \(hangMonitor.maxObservedMs)ms (limit \(SpecImportPerformanceSLO.mainThreadHangLimitMs)ms)"
        )

        if ProcessInfo.processInfo.environment["UPDATE_SPEC_PERF_BASELINE"] == "1" {
            try writeBaseline(
                SpecImportPerformanceBaseline(
                    fixture: "stress-500",
                    metric: "preview_p95_seconds",
                    p95Seconds: p95Seconds,
                    sampleCount: SpecImportPerformanceSLO.sampleCount,
                    recordedAt: ISO8601DateFormatter().string(from: Date()),
                    platform: "macOS"
                ),
                named: "stress-500"
            )
        }
    }

    // MARK: - Helpers

    private func previewStress500(bytes: Data) async throws -> SpecImportPreview {
        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .yaml,
            source: .file
        )
        #expect(preview.operationCount == 500)
        return preview
    }

    private func fixtureBytes(named name: String) throws -> Data {
        let url = Self.fixturesDirectory.appendingPathComponent("\(name).input.yaml")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FixtureError.missingInput(name)
        }
        return try Data(contentsOf: url)
    }

    private func loadBaseline(named name: String) throws -> SpecImportPerformanceBaseline? {
        let url = Self.fixturesDirectory.appendingPathComponent("\(name).performance-baseline.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try JSONDecoder().decode(SpecImportPerformanceBaseline.self, from: Data(contentsOf: url))
    }

    private func writeBaseline(_ baseline: SpecImportPerformanceBaseline, named name: String) throws {
        let url = Self.fixturesDirectory.appendingPathComponent("\(name).performance-baseline.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(baseline).write(to: url, options: .atomic)
    }

    private enum FixtureError: Error {
        case missingInput(String)
    }
}