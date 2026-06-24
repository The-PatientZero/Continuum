//
//  MenuBarBlockedItemRecoveryExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Executes recovery for items stranded at macOS's blocked x=-1 position.
///
/// Selection and destination policy stay pure in `MenuBarBlockedItemRecoveryPolicy`.
/// This executor owns the bounded observe-resolve-move-settle runtime sequence so
/// callers can keep platform concerns such as HID event pausing at the edge.
enum MenuBarBlockedItemRecoveryExecutor {
    enum StopReason: Equatable {
        case completed
        case noCandidates
        case controlItemsMissing
    }

    struct Outcome: Equatable {
        let attemptedCount: Int
        let restoredCount: Int
        let failedCount: Int
        let stopReason: StopReason
    }

    @MainActor
    static func execute(
        items: [MenuBarItem],
        controlItemWindowIDs: MenuBarControlItemWindowIDs,
        currentBoundsForItem: (MenuBarItem) -> CGRect?,
        moveItem: (MenuBarItem, MenuBarMoveDestination) async throws -> Void,
        recordNoCandidates: () -> Void = {},
        recordCandidatesFound: (Int) -> Void = { _ in },
        recordControlItemsMissing: (Int) -> Void = { _ in },
        beginMoveSession: () -> Void = {},
        endMoveSession: () -> Void = {},
        recordMoveSuccess: (MenuBarItem) -> Void = { _ in },
        recordMoveFailure: (MenuBarItem, Error) -> Void = { _, _ in },
        sleepAfterRecovery: (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> Outcome {
        let blockedItems = MenuBarBlockedItemRecoveryPolicy.recoveryCandidates(
            from: items,
            currentBoundsForItem: currentBoundsForItem
        )

        guard !blockedItems.isEmpty else {
            recordNoCandidates()
            return Outcome(
                attemptedCount: 0,
                restoredCount: 0,
                failedCount: 0,
                stopReason: .noCandidates
            )
        }

        recordCandidatesFound(blockedItems.count)

        var itemsCopy = items
        guard let controlItems = MenuBarControlItems(
            items: &itemsCopy,
            windowIDs: controlItemWindowIDs
        ) else {
            recordControlItemsMissing(blockedItems.count)
            return Outcome(
                attemptedCount: blockedItems.count,
                restoredCount: 0,
                failedCount: blockedItems.count,
                stopReason: .controlItemsMissing
            )
        }

        let destination = MenuBarBlockedItemRecoveryPolicy.visibleRecoveryDestination(
            hiddenControlItem: controlItems.hidden
        )
        var failedCount = 0

        beginMoveSession()
        defer {
            endMoveSession()
        }

        for item in blockedItems {
            do {
                try await moveItem(item, destination)
                recordMoveSuccess(item)
            } catch {
                failedCount += 1
                recordMoveFailure(item, error)
            }
        }

        if !Task.isCancelled {
            await sleepAfterRecovery(.milliseconds(200))
        }

        return Outcome(
            attemptedCount: blockedItems.count,
            restoredCount: blockedItems.count - failedCount,
            failedCount: failedCount,
            stopReason: .completed
        )
    }
}
