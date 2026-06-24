//
//  MenuBarDiagnosticsRuntime.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Runtime owner for menu bar health, snapshots, and degradation latches.
///
/// Keeping the missing-control-items latch with diagnostics prevents the
/// manager from coordinating two separate health states during cache churn.
struct MenuBarDiagnosticsRuntime: Equatable {
    private(set) var diagnostics = MenuBarRuntimeDiagnostics()
    private(set) var areControlItemsMissing = false

    var state: MenuBarRuntimeState {
        diagnostics.state
    }

    var lastSnapshot: MenuBarSnapshot? {
        diagnostics.lastSnapshot
    }

    mutating func markState(_ state: MenuBarRuntimeState) {
        diagnostics.markState(state)
    }

    mutating func markControlItemsAvailable() {
        areControlItemsMissing = false
    }

    mutating func recordSnapshot(
        cache: MenuBarItemCache,
        controlItemsMissing: Bool? = nil,
        systemMenuBarHidden: Bool,
        createdAt: Date = Date()
    ) {
        let snapshot = MenuBarSnapshot(
            cache: cache,
            controlItemsMissing: controlItemsMissing ?? areControlItemsMissing,
            systemMenuBarHidden: systemMenuBarHidden,
            createdAt: createdAt
        )
        diagnostics.recordSnapshot(snapshot)
    }

    mutating func recordZeroItemObservation(
        preserving cache: MenuBarItemCache,
        systemMenuBarHidden: Bool,
        detail: String,
        createdAt: Date = Date()
    ) {
        diagnostics.recordZeroItemObservation(
            preserving: MenuBarSnapshot(
                cache: cache,
                controlItemsMissing: false,
                systemMenuBarHidden: systemMenuBarHidden,
                createdAt: createdAt
            ),
            detail: detail
        )
    }

    mutating func recordControlItemMiss(
        detail: String,
        preserving cache: MenuBarItemCache,
        systemMenuBarHidden: Bool
    ) {
        areControlItemsMissing = true
        diagnostics.recordControlItemMiss(detail: detail)
        recordSnapshot(
            cache: cache,
            controlItemsMissing: true,
            systemMenuBarHidden: systemMenuBarHidden
        )
    }

    mutating func recordCloneWindowsDropped(_ count: Int) {
        diagnostics.recordCloneWindowsDropped(count)
    }

    mutating func recordIdentityCorrections(_ count: Int) {
        diagnostics.recordIdentityCorrections(count)
    }

    mutating func recordOperationFailure(detail: String) {
        diagnostics.recordOperationFailure(detail: detail)
    }
}
