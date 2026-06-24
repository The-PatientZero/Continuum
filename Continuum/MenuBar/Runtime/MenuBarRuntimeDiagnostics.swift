//
//  MenuBarRuntimeDiagnostics.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// High-level runtime state for the menu bar control loop.
enum MenuBarRuntimeState: Equatable, CustomStringConvertible {
    case idle
    case observing
    case planning
    case applying
    case verifying
    case recovering
    case degraded(MenuBarRuntimeFailure)

    var description: String {
        switch self {
        case .idle:
            "idle"
        case .observing:
            "observing"
        case .planning:
            "planning"
        case .applying:
            "applying"
        case .verifying:
            "verifying"
        case .recovering:
            "recovering"
        case let .degraded(failure):
            "degraded(\(failure.reason))"
        }
    }
}

/// A bounded reason for degraded behavior.
struct MenuBarRuntimeFailure: Equatable, CustomStringConvertible {
    enum Reason: String {
        case zeroItems
        case missingControlItems
        case identityDrift
        case systemMenuBarHidden
        case operationFailed
    }

    let reason: Reason
    let detail: String
    let occurredAt: Date

    init(reason: Reason, detail: String, occurredAt: Date = Date()) {
        self.reason = reason
        self.detail = detail
        self.occurredAt = occurredAt
    }

    var description: String {
        "\(reason.rawValue): \(detail)"
    }
}

/// Diagnostics produced by the runtime control loop.
///
/// This is intentionally compact: it gives the UI, logs, and future MCP-style
/// controls a single place to inspect current health without adding another
/// polling or screen-observation path.
struct MenuBarRuntimeDiagnostics: Equatable {
    var state: MenuBarRuntimeState = .idle
    var lastSnapshot: MenuBarSnapshot?
    var lastFailure: MenuBarRuntimeFailure?
    var cacheCycles = 0
    var zeroItemSnapshots = 0
    var cloneWindowsDropped = 0
    var controlItemMisses = 0
    var identityCorrections = 0

    var isDegraded: Bool {
        if case .degraded = state {
            return true
        }
        return false
    }

    var unresolvedIdentityCount: Int {
        lastSnapshot?.unresolvedItems.count ?? 0
    }

    mutating func markState(_ state: MenuBarRuntimeState) {
        self.state = state
    }

    mutating func recordSnapshot(
        _ snapshot: MenuBarSnapshot,
        zeroItemsDetail: String = "Menu bar snapshot contained no items"
    ) {
        lastSnapshot = snapshot
        cacheCycles += 1

        if snapshot.itemCount == 0 {
            zeroItemSnapshots += 1
        }

        if snapshot.systemMenuBarHidden {
            recordFailure(
                MenuBarRuntimeFailure(
                    reason: .systemMenuBarHidden,
                    detail: "System menu bar is hidden or auto-hidden"
                )
            )
            return
        }

        if snapshot.controlItemsMissing {
            recordFailure(
                MenuBarRuntimeFailure(
                    reason: .missingControlItems,
                    detail: "Continuum control items were not found in the menu bar snapshot"
                )
            )
            return
        }

        if snapshot.itemCount == 0 {
            recordFailure(
                MenuBarRuntimeFailure(
                    reason: .zeroItems,
                    detail: zeroItemsDetail
                )
            )
            return
        }

        state = .idle
    }

    mutating func recordZeroItemObservation(
        preserving snapshot: MenuBarSnapshot,
        detail: String
    ) {
        lastSnapshot = snapshot
        cacheCycles += 1
        zeroItemSnapshots += 1
        recordFailure(
            MenuBarRuntimeFailure(
                reason: .zeroItems,
                detail: detail
            )
        )
    }

    mutating func recordCloneWindowsDropped(_ count: Int) {
        guard count > 0 else { return }
        cloneWindowsDropped += count
    }

    mutating func recordIdentityCorrections(_ count: Int) {
        guard count > 0 else { return }
        identityCorrections += count
        lastFailure = MenuBarRuntimeFailure(
            reason: .identityDrift,
            detail: "\(count) source PID correction(s) applied in the current cache cycle"
        )
    }

    mutating func recordControlItemMiss(detail: String) {
        controlItemMisses += 1
        recordFailure(
            MenuBarRuntimeFailure(
                reason: .missingControlItems,
                detail: detail
            )
        )
    }

    mutating func recordOperationFailure(detail: String) {
        recordFailure(
            MenuBarRuntimeFailure(
                reason: .operationFailed,
                detail: detail
            )
        )
    }

    private mutating func recordFailure(_ failure: MenuBarRuntimeFailure) {
        lastFailure = failure
        state = .degraded(failure)
    }
}
