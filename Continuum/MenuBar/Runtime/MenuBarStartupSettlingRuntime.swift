//
//  MenuBarStartupSettlingRuntime.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Mutable runtime state for startup/app-restart settling windows.
///
/// The pure startup settling policy decides whether a window should start and
/// when polling has settled. This runtime object owns the live task handles and
/// active-window metadata so launch-time restore gating has one explicit owner.
struct MenuBarStartupSettlingRuntime {
    enum StartDecision: Equatable {
        case ignore(kindDescription: String)
        case start(MenuBarStartupSettlingPolicy.StartConfiguration)
    }

    private(set) var isActive = false

    private var settlingTask: Task<Void, Never>?
    private var initialCacheTask: Task<Void, Never>?
    private var deadline: ContinuousClock.Instant?
    private var expectedBundleIDs = Set<String>()
    private var kind: MenuBarStartupSettlingPolicy.Kind?

    var currentSettlingTask: Task<Void, Never>? {
        settlingTask
    }

    var currentInitialCacheTask: Task<Void, Never>? {
        initialCacheTask
    }

    mutating func cancelInitialCacheTask() {
        initialCacheTask?.cancel()
        initialCacheTask = nil
    }

    mutating func attachInitialCacheTask(_ task: Task<Void, Never>) {
        initialCacheTask = task
    }

    mutating func planStart(
        reason: String,
        incomingExpectedBundleIDs: Set<String>,
        now: ContinuousClock.Instant = .now,
        maxDuration: Duration
    ) -> StartDecision {
        let startDecision = MenuBarStartupSettlingPolicy.planStart(
            reason: reason,
            existingKind: kind,
            existingExpectedBundleIDs: expectedBundleIDs,
            existingDeadline: deadline,
            incomingExpectedBundleIDs: incomingExpectedBundleIDs,
            now: now,
            maxDuration: maxDuration
        )

        switch startDecision {
        case let .ignore(mergedExpectedBundleIDs):
            expectedBundleIDs = mergedExpectedBundleIDs
            return .ignore(kindDescription: kind?.description ?? "unknown")
        case let .start(configuration):
            settlingTask?.cancel()
            settlingTask = nil
            deadline = configuration.deadline
            expectedBundleIDs = configuration.expectedBundleIDs
            kind = configuration.kind
            isActive = true
            return .start(configuration)
        }
    }

    mutating func attachSettlingTask(_ task: Task<Void, Never>) {
        settlingTask = task
    }

    mutating func finishSettling() {
        clearSettlingState()
    }

    mutating func cancelSettling() {
        settlingTask?.cancel()
        clearSettlingState()
    }

    mutating func cancelAll() {
        cancelInitialCacheTask()
        cancelSettling()
    }

    private mutating func clearSettlingState() {
        settlingTask = nil
        isActive = false
        deadline = nil
        expectedBundleIDs.removeAll()
        kind = nil
    }
}
