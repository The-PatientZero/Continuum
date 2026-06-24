//
//  MenuBarSyntheticEventRuntime.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Mutable runtime state for synthetic menu-bar move and click operations.
///
/// The manager still performs CGEvent creation, posting, and observation.
/// This runtime object owns the lightweight state that determines operation
/// pacing, adaptive timeouts, cursor ownership, and event serialization.
struct MenuBarSyntheticEventRuntime {
    let operationGate = MenuBarEventOperationGate()

    private var lastMoveOperationTimestamp: ContinuousClock.Instant?
    private var timeoutCache = MenuBarEventTimeoutCache()
    private(set) var cursorManagementIsSuppressed = false

    var shouldManageCursor: Bool {
        !cursorManagementIsSuppressed
    }

    func lastMoveOperationOccurred(
        within duration: Duration,
        now: ContinuousClock.Instant = .now
    ) -> Bool {
        guard let timestamp = lastMoveOperationTimestamp else {
            return false
        }
        return timestamp.duration(to: now) <= duration
    }

    func moveOperationBuffer(now: ContinuousClock.Instant = .now) -> Duration? {
        guard let timestamp = lastMoveOperationTimestamp else {
            return nil
        }
        return MenuBarEventPacingPolicy.moveOperationBuffer(
            elapsedSinceLastMove: timestamp.duration(to: now)
        )
    }

    mutating func recordMoveOperation(now: ContinuousClock.Instant = .now) {
        lastMoveOperationTimestamp = now
    }

    func moveTimeout(for item: MenuBarItem) -> Duration {
        timeoutCache.moveTimeout(for: item)
    }

    mutating func recordMoveFinished(
        timeout: Duration,
        for item: MenuBarItem,
        now: ContinuousClock.Instant = .now
    ) {
        recordMoveOperation(now: now)
        timeoutCache.updateMoveTimeout(timeout, for: item)
    }

    func clickTimeout(for item: MenuBarItem) -> Duration {
        timeoutCache.clickTimeout(for: item)
    }

    @discardableResult
    mutating func recordClickSuccess(
        _ measured: Duration,
        for item: MenuBarItem
    ) -> Duration {
        timeoutCache.updateClickTimeout(measured, for: item)
    }

    mutating func pruneTimeouts(keeping items: [MenuBarItem]) {
        let validTags = Set(items.map(\.tag))
        timeoutCache.pruneMoveTimeouts(keeping: validTags)
        timeoutCache.pruneClickTimeouts(keeping: validTags)
    }

    mutating func beginCursorManagementSuppression() {
        cursorManagementIsSuppressed = true
    }

    mutating func endCursorManagementSuppression() {
        cursorManagementIsSuppressed = false
    }
}
