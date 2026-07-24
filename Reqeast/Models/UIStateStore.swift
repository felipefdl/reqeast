//
//  UIStateStore.swift
//  Reqeast
//

import Foundation

@MainActor
@Observable
final class UIStateStore {
    static let shared = UIStateStore()

    private static let storageKey = "reqeast.uiState"
    private static let globalResponseTabKey = "reqeast.globalResponseTab"
    private static let globalResponseViewModeKey = "reqeast.globalResponseViewMode"
    private static let globalResponseFormatOverrideKey = "reqeast.globalResponseFormatOverride"

    private(set) var states: [UUID: RequestUIState] = [:]
    private var saveTask: Task<Void, Never>?

    // MARK: - Global Response State

    var globalResponseTab: HttpResponseTab {
        didSet { UserDefaults.standard.set(globalResponseTab.rawValue, forKey: Self.globalResponseTabKey) }
    }

    var globalResponseViewMode: ResponseViewMode {
        didSet { UserDefaults.standard.set(globalResponseViewMode.rawValue, forKey: Self.globalResponseViewModeKey) }
    }

    var globalResponseFormatOverride: ResponseFormatOverride {
        didSet {
            UserDefaults.standard.set(globalResponseFormatOverride.rawValue, forKey: Self.globalResponseFormatOverrideKey)
        }
    }

    /// Tracks whether a response-area field (e.g. jq filter) has keyboard focus on iOS.
    /// Prevents the response panel from being hidden when the keyboard is up.
    var isResponseFieldFocused = false

    /// Session-only split ratios (not persisted across app launches)
    private var splitRatios: [UUID: CGFloat] = [:]

    func splitRatio(for requestId: UUID) -> CGFloat {
        splitRatios[requestId] ?? 0.55
    }

    func setSplitRatio(_ ratio: CGFloat, for requestId: UUID) {
        splitRatios[requestId] = ratio
    }

    private init() {
        let defaults = UserDefaults.standard
        self.globalResponseTab = defaults.string(forKey: Self.globalResponseTabKey)
            .flatMap(HttpResponseTab.init(rawValue:)) ?? .body
        self.globalResponseViewMode = defaults.string(forKey: Self.globalResponseViewModeKey)
            .flatMap(ResponseViewMode.init(rawValue:)) ?? .pretty
        self.globalResponseFormatOverride = defaults.string(forKey: Self.globalResponseFormatOverrideKey)
            .flatMap(ResponseFormatOverride.init(rawValue:)) ?? .auto
        load()
    }

    func state(for requestId: UUID) -> RequestUIState {
        states[requestId] ?? RequestUIState()
    }

    func update(for requestId: UUID, _ transform: (inout RequestUIState) -> Void) {
        var current = states[requestId] ?? RequestUIState()
        transform(&current)
        states[requestId] = current
        scheduleSave()
    }

    func removeState(for requestId: UUID) {
        guard states.removeValue(forKey: requestId) != nil else { return }
        scheduleSave()
    }

    func resetAll() {
        states.removeAll()
        globalResponseTab = .body
        globalResponseViewMode = .pretty
        globalResponseFormatOverride = .auto
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.globalResponseTabKey)
        defaults.removeObject(forKey: Self.globalResponseViewModeKey)
        defaults.removeObject(forKey: Self.globalResponseFormatOverrideKey)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([UUID: RequestUIState].self, from: data)
        else { return }
        states = decoded
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(states) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
