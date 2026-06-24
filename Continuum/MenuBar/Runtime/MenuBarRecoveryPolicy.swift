//
//  MenuBarRecoveryPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Recovery action recommended by the read-only menu bar runtime.
enum MenuBarRuntimeRecoveryAction: Equatable, CustomStringConvertible {
    case none
    case waitForMenuBarVisibility
    case rescanObservedWindows
    case reacquireControlItems
    case preserveKnownGoodCache
    case restoreBlockedItemsToVisible

    var description: String {
        switch self {
        case .none:
            "none"
        case .waitForMenuBarVisibility:
            "waitForMenuBarVisibility"
        case .rescanObservedWindows:
            "rescanObservedWindows"
        case .reacquireControlItems:
            "reacquireControlItems"
        case .preserveKnownGoodCache:
            "preserveKnownGoodCache"
        case .restoreBlockedItemsToVisible:
            "restoreBlockedItemsToVisible"
        }
    }
}

/// Pure policy for choosing the next recovery step from runtime state.
enum MenuBarRecoveryPolicy {
    static func recommendedAction(
        state: MenuBarRuntimeState,
        snapshot: MenuBarSnapshot
    ) -> MenuBarRuntimeRecoveryAction {
        if case let .degraded(failure) = state {
            return recommendedAction(for: failure.reason)
        }

        if snapshot.systemMenuBarHidden {
            return .waitForMenuBarVisibility
        }
        if snapshot.controlItemsMissing {
            return .reacquireControlItems
        }
        if snapshot.itemCount == 0 {
            return .preserveKnownGoodCache
        }
        if !snapshot.blockedItems.isEmpty {
            return .restoreBlockedItemsToVisible
        }
        if !snapshot.invalidItems.isEmpty {
            return .rescanObservedWindows
        }
        return .none
    }

    private static func recommendedAction(
        for reason: MenuBarRuntimeFailure.Reason
    ) -> MenuBarRuntimeRecoveryAction {
        switch reason {
        case .systemMenuBarHidden:
            .waitForMenuBarVisibility
        case .missingControlItems:
            .reacquireControlItems
        case .zeroItems:
            .preserveKnownGoodCache
        case .identityDrift, .operationFailed:
            .rescanObservedWindows
        }
    }
}
