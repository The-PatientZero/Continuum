//
//  MenuBarBlockedMoveRecoveryExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Executes the bounded recovery path for one move that strands an item at x=-1.
///
/// `MenuBarMoveRecoveryPolicy` decides whether recovery is valid. This executor
/// owns the runtime sequence needed to re-anchor the item on the visible side of
/// the hidden control item.
enum MenuBarBlockedMoveRecoveryExecutor {
    enum StopReason: Equatable {
        case completed
        case hiddenControlItemMissing
        case missingHiddenControlWindow
        case moveFailed
        case notNeeded
        case observationUnavailable
    }

    struct Outcome: Equatable {
        let attemptedRecovery: Bool
        let recovered: Bool
        let stopReason: StopReason
    }

    @MainActor
    static func execute(
        command: MenuBarMoveCommand,
        displayID: CGDirectDisplayID,
        itemIsBlocked: () async -> Bool,
        controlItemWindowIDs: MenuBarControlItemWindowIDs,
        observeItems: () async -> [MenuBarItem]?,
        moveItem: (MenuBarItem, MenuBarMoveDestination, CGDirectDisplayID) async throws -> Void,
        recordRecoveryStart: (MenuBarItem) -> Void = { _ in },
        recordMissingHiddenControlWindow: (MenuBarItem) -> Void = { _ in },
        recordObservationUnavailable: (MenuBarItem) -> Void = { _ in },
        recordHiddenControlItemMissing: (MenuBarItem) -> Void = { _ in },
        recordRecoverySuccess: (MenuBarItem) -> Void = { _ in },
        recordRecoveryFailure: (MenuBarItem, Error) -> Void = { _, _ in }
    ) async -> Outcome {
        let item = command.item
        let recoveryDecision = await MenuBarMoveRecoveryPolicy.decision(
            after: command,
            itemIsBlocked: itemIsBlocked()
        )
        guard recoveryDecision == .restoreToVisible else {
            return Outcome(
                attemptedRecovery: false,
                recovered: false,
                stopReason: .notNeeded
            )
        }

        recordRecoveryStart(item)

        guard let hiddenControlItemWindowID = controlItemWindowIDs.hidden else {
            recordMissingHiddenControlWindow(item)
            return Outcome(
                attemptedRecovery: true,
                recovered: false,
                stopReason: .missingHiddenControlWindow
            )
        }

        guard let items = await observeItems() else {
            recordObservationUnavailable(item)
            return Outcome(
                attemptedRecovery: true,
                recovered: false,
                stopReason: .observationUnavailable
            )
        }

        guard let hiddenMenuBarItem = items.first(
            where: { $0.windowID == hiddenControlItemWindowID }
        ) else {
            recordHiddenControlItemMissing(item)
            return Outcome(
                attemptedRecovery: true,
                recovered: false,
                stopReason: .hiddenControlItemMissing
            )
        }

        do {
            try await moveItem(
                item,
                MenuBarMoveRecoveryPolicy.visibleRecoveryDestination(
                    hiddenControlItem: hiddenMenuBarItem
                ),
                displayID
            )
            recordRecoverySuccess(item)
            return Outcome(
                attemptedRecovery: true,
                recovered: true,
                stopReason: .completed
            )
        } catch {
            recordRecoveryFailure(item, error)
            return Outcome(
                attemptedRecovery: true,
                recovered: false,
                stopReason: .moveFailed
            )
        }
    }
}
