//
//  MenuBarLayoutMutationState.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Mutable runtime state for layout-wide mutation operations.
///
/// Layout reset and saved-layout restore both temporarily make cache snapshots
/// unsafe to persist as the user's intended order. Keeping their lifecycle in
/// one small state object makes cache-save suppression and stale recovery
/// explicit instead of scattering Boolean flag transitions through the manager.
struct MenuBarLayoutMutationState: Equatable {
    private(set) var isResettingLayout = false
    private(set) var isRestoringItemOrder = false
    private(set) var restoringItemOrderStartedAt: Date?

    mutating func beginReset() {
        isResettingLayout = true
    }

    mutating func endReset() {
        isResettingLayout = false
    }

    mutating func beginSavedLayoutRestore(now: Date = Date()) {
        isRestoringItemOrder = true
        restoringItemOrderStartedAt = now
    }

    mutating func endSavedLayoutRestore() {
        isRestoringItemOrder = false
        restoringItemOrderStartedAt = nil
    }

    mutating func clearStaleSavedLayoutRestoreIfNeeded(now: Date = Date()) -> Bool {
        let action = MenuBarCacheCommitPolicy.restorationFlagAction(
            isRestoringItemOrder: isRestoringItemOrder,
            startedAt: restoringItemOrderStartedAt,
            now: now
        )
        guard action == .clearStale else {
            return false
        }

        endSavedLayoutRestore()
        return true
    }
}
