//
//  MenuBarLayoutResetExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Executes the live reset sequence that moves eligible items to Hidden.
///
/// `MenuBarLayoutResetPolicy` owns eligibility and retry decisions. This
/// executor owns the runtime sequence around those decisions: observation,
/// control-item recovery, divider ordering, move execution, and the second
/// pass after macOS has settled the first set of moves.
enum MenuBarLayoutResetExecutor {
    enum StopReason: Equatable {
        case completed
        case initialObservationUnavailable
        case retryObservationUnavailable
        case controlItemsMissing
    }

    struct Outcome: Equatable {
        let firstPassMoveCount: Int
        let firstPassFailureCount: Int
        let secondPassMoveCount: Int
        let failedMoveCount: Int
        let controlRecoveryAttempted: Bool
        let stopReason: StopReason
    }

    struct Operations {
        let observeItems: (String) async -> [MenuBarItem]?
        let setAlwaysHiddenSectionEnabled: (Bool) -> Void
        let enforceControlItemOrder: (MenuBarControlItems) async -> Void
        let moveItem: (MenuBarItem, MenuBarMoveDestination) async throws -> Void
        let boundsForItem: (MenuBarItem) -> CGRect
        let sleep: (Duration) async -> Void
    }

    struct Diagnostics {
        var recordMissingControlItems: () -> Void = {}
        var recordControlRecoverySuccess: () -> Void = {}
        var recordSecondPassStart: (Int) -> Void = { _ in }
        var recordMoveFailure: (MenuBarItem, Error) -> Void = { _, _ in }
    }

    private struct ResolvedControlItems {
        let items: [MenuBarItem]
        let controlItems: MenuBarControlItems
    }

    private struct MovePassOutcome: Equatable {
        let movedCount: Int
        let failedCount: Int
    }

    @MainActor
    static func execute(
        alwaysHiddenSectionEnabled: Bool,
        controlItemWindowIDs: MenuBarControlItemWindowIDs,
        operations: Operations,
        diagnostics: Diagnostics = Diagnostics()
    ) async -> Outcome {
        guard let initialItems = await operations.observeItems("layoutResetInitial") else {
            return Outcome(
                firstPassMoveCount: 0,
                firstPassFailureCount: 0,
                secondPassMoveCount: 0,
                failedMoveCount: 0,
                controlRecoveryAttempted: false,
                stopReason: .initialObservationUnavailable
            )
        }

        let controlRecoveryAttempted: Bool
        let resolved: ResolvedControlItems
        if let initialResolved = resolveControlItems(
            from: initialItems,
            windowIDs: controlItemWindowIDs
        ) {
            controlRecoveryAttempted = false
            resolved = initialResolved
        } else {
            diagnostics.recordMissingControlItems()
            guard MenuBarLayoutResetPolicy.controlRecoveryAction(
                alwaysHiddenSectionEnabled: alwaysHiddenSectionEnabled
            ) == .toggleAlwaysHiddenSection else {
                return Outcome(
                    firstPassMoveCount: 0,
                    firstPassFailureCount: 0,
                    secondPassMoveCount: 0,
                    failedMoveCount: 0,
                    controlRecoveryAttempted: false,
                    stopReason: .controlItemsMissing
                )
            }

            controlRecoveryAttempted = true
            operations.setAlwaysHiddenSectionEnabled(false)
            await operations.sleep(MenuBarLayoutResetPolicy.delay(after: .controlRecoveryDisableSettle))
            operations.setAlwaysHiddenSectionEnabled(true)
            await operations.sleep(MenuBarLayoutResetPolicy.delay(after: .controlRecoveryEnableSettle))

            guard let retryItems = await operations.observeItems("layoutResetControlRetry") else {
                return Outcome(
                    firstPassMoveCount: 0,
                    firstPassFailureCount: 0,
                    secondPassMoveCount: 0,
                    failedMoveCount: 0,
                    controlRecoveryAttempted: true,
                    stopReason: .retryObservationUnavailable
                )
            }
            guard let retryResolved = resolveControlItems(
                from: retryItems,
                windowIDs: controlItemWindowIDs
            ) else {
                return Outcome(
                    firstPassMoveCount: 0,
                    firstPassFailureCount: 0,
                    secondPassMoveCount: 0,
                    failedMoveCount: 0,
                    controlRecoveryAttempted: true,
                    stopReason: .controlItemsMissing
                )
            }

            diagnostics.recordControlRecoverySuccess()
            resolved = retryResolved
        }

        await operations.enforceControlItemOrder(resolved.controlItems)

        let firstPass = await movePass(
            items: resolved.items,
            anchor: resolved.controlItems.hidden,
            operations: operations,
            diagnostics: diagnostics
        )

        await operations.sleep(MenuBarLayoutResetPolicy.delay(after: .firstPassSettle))

        let secondPass = await secondPass(
            controlItemWindowIDs: controlItemWindowIDs,
            operations: operations,
            diagnostics: diagnostics
        )

        return Outcome(
            firstPassMoveCount: firstPass.movedCount,
            firstPassFailureCount: firstPass.failedCount,
            secondPassMoveCount: secondPass.movedCount,
            failedMoveCount: secondPass.failedCount,
            controlRecoveryAttempted: controlRecoveryAttempted,
            stopReason: .completed
        )
    }

    private static func resolveControlItems(
        from items: [MenuBarItem],
        windowIDs: MenuBarControlItemWindowIDs
    ) -> ResolvedControlItems? {
        var resolvedItems = items
        guard let controlItems = MenuBarControlItems(
            items: &resolvedItems,
            windowIDs: windowIDs
        ) else {
            return nil
        }
        return ResolvedControlItems(items: resolvedItems, controlItems: controlItems)
    }

    @MainActor
    private static func movePass(
        items: [MenuBarItem],
        anchor: MenuBarItem,
        operations: Operations,
        diagnostics: Diagnostics
    ) async -> MovePassOutcome {
        var movedCount = 0
        var failedCount = 0
        for item in MenuBarLayoutResetPolicy.moveCandidates(from: items) {
            do {
                try await operations.moveItem(item, .leftOfItem(anchor))
                movedCount += 1
            } catch {
                failedCount += 1
                diagnostics.recordMoveFailure(item, error)
            }
        }
        return MovePassOutcome(movedCount: movedCount, failedCount: failedCount)
    }

    @MainActor
    private static func secondPass(
        controlItemWindowIDs: MenuBarControlItemWindowIDs,
        operations: Operations,
        diagnostics: Diagnostics
    ) async -> MovePassOutcome {
        guard let refreshedItems = await operations.observeItems("layoutResetSecondPass"),
              let refreshed = resolveControlItems(
                from: refreshedItems,
                windowIDs: controlItemWindowIDs
              )
        else {
            return MovePassOutcome(movedCount: 0, failedCount: 0)
        }

        let hiddenControlBounds = operations.boundsForItem(refreshed.controlItems.hidden)
        let alwaysHiddenControlBounds = refreshed.controlItems.alwaysHidden.map {
            operations.boundsForItem($0)
        }

        let candidates = MenuBarLayoutResetPolicy.secondPassCandidates(
            items: refreshed.items,
            hiddenControlBounds: hiddenControlBounds,
            alwaysHiddenControlBounds: alwaysHiddenControlBounds,
            boundsForItem: operations.boundsForItem
        )
        guard !candidates.isEmpty else {
            return MovePassOutcome(movedCount: 0, failedCount: 0)
        }

        diagnostics.recordSecondPassStart(candidates.count)
        return await movePass(
            items: candidates,
            anchor: refreshed.controlItems.hidden,
            operations: operations,
            diagnostics: diagnostics
        )
    }
}
