//
//  MenuBarMenuOpenProbeRuntime.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Mutable runtime state for the "is any menu open?" probe.
///
/// The policy owns cache freshness rules and window/PID decisions. This runtime
/// state owns the positive-result cache and shared in-flight task so smart
/// rehide callers do not stampede the WindowServer during menu-bar churn.
struct MenuBarMenuOpenProbeRuntime {
    private var inFlightTask: Task<Bool, Never>?
    private var cachedResult: Bool?
    private var cachedAt: ContinuousClock.Instant?

    var currentTask: Task<Bool, Never>? {
        inFlightTask
    }

    func cachedResultDecision(
        now: ContinuousClock.Instant = .now
    ) -> MenuBarMenuOpenProbePolicy.CachedResultDecision {
        MenuBarMenuOpenProbePolicy.cachedResultDecision(
            cachedResult: cachedResult,
            cachedAt: cachedAt,
            now: now
        )
    }

    mutating func start(_ task: Task<Bool, Never>) {
        inFlightTask = task
    }

    mutating func finish(result: Bool, now: ContinuousClock.Instant = .now) {
        inFlightTask = nil
        if result {
            cachedResult = true
            cachedAt = now
        } else {
            cachedResult = nil
            cachedAt = nil
        }
    }

    mutating func cancel() {
        inFlightTask?.cancel()
        inFlightTask = nil
    }
}
