//
//  MenuBarPendingRelocationExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Executes one pending-relocation recovery pass.
///
/// `PendingLedger` owns the per-entry planning decision. This executor owns the
/// runtime loop around those decisions: malformed-entry cleanup, wait-for-
/// relaunch promotion, move execution, successful-entry clearing, and persistence.
enum MenuBarPendingRelocationExecutor {
    struct Outcome: Equatable {
        let didRelocate: Bool
        let movedCount: Int
        let clearedCount: Int
        let promotedCount: Int
        let failedMoveCount: Int
    }

    struct Operations {
        let pendingEntry: (String) -> PendingLedger.PendingEntry?
        let clearEntry: (String) -> Void
        let promoteWaitForRelaunch: (String, MenuBarSection.Name) -> Void
        let persistPendingRelocations: () -> Void
        let moveItem: (MenuBarItem, MenuBarMoveDestination) async throws -> Void
    }

    struct Diagnostics {
        var recordMalformedEntry: (String) -> Void = { _ in }
        var recordWaitForRelaunchPromotion: (MenuBarItem) -> Void = { _ in }
        var recordMoveStart: (MenuBarItem, MenuBarSection.Name) -> Void = { _, _ in }
        var recordMoveFailure: (MenuBarItem, MenuBarSection.Name, Error) -> Void = { _, _, _ in }
        var recordWaitForRelaunchActive: (MenuBarItem) -> Void = { _ in }
    }

    @MainActor
    static func execute(
        tagIdentifiers: [String],
        items: [MenuBarItem],
        controlItems: MenuBarControlItems,
        hiddenBounds: CGRect,
        boundsForWindowID: [CGWindowID: CGRect],
        planningInput: PendingLedger.RelocationPlanningInput,
        operations: Operations,
        diagnostics: Diagnostics = Diagnostics()
    ) async -> Outcome {
        var movedCount = 0
        var clearedCount = 0
        var promotedCount = 0
        var failedMoveCount = 0

        for tagIdentifier in tagIdentifiers {
            guard let entry = operations.pendingEntry(tagIdentifier) else {
                diagnostics.recordMalformedEntry(tagIdentifier)
                operations.clearEntry(tagIdentifier)
                clearedCount += 1
                continue
            }

            var activeEntry = entry
            var decision = plan(
                entry: activeEntry,
                items: items,
                controlItems: controlItems,
                hiddenBounds: hiddenBounds,
                boundsForWindowID: boundsForWindowID,
                planningInput: planningInput
            )

            if case let .promoteWaitForRelaunch(promotedSection) = decision {
                if let item = item(matching: tagIdentifier, in: items) {
                    diagnostics.recordWaitForRelaunchPromotion(item)
                }
                operations.promoteWaitForRelaunch(tagIdentifier, promotedSection)
                operations.persistPendingRelocations()
                promotedCount += 1

                activeEntry = PendingLedger.PendingEntry(
                    tagIdentifier: tagIdentifier,
                    kind: .section(promotedSection)
                )
                decision = plan(
                    entry: activeEntry,
                    items: items,
                    controlItems: controlItems,
                    hiddenBounds: hiddenBounds,
                    boundsForWindowID: boundsForWindowID,
                    planningInput: planningInput
                )
            }

            switch decision {
            case let .move(item, destination):
                do {
                    diagnostics.recordMoveStart(item, activeEntry.targetSection)
                    try await operations.moveItem(item, destination)
                    operations.clearEntry(tagIdentifier)
                    movedCount += 1
                    clearedCount += 1
                } catch {
                    diagnostics.recordMoveFailure(item, activeEntry.targetSection, error)
                    failedMoveCount += 1
                }

            case .clearEntry:
                operations.clearEntry(tagIdentifier)
                clearedCount += 1

            case .promoteWaitForRelaunch:
                break

            case let .skip(reason):
                if case .waitForRelaunchActive = reason,
                   let item = item(matching: tagIdentifier, in: items)
                {
                    diagnostics.recordWaitForRelaunchActive(item)
                }
            }
        }

        operations.persistPendingRelocations()
        return Outcome(
            didRelocate: movedCount > 0,
            movedCount: movedCount,
            clearedCount: clearedCount,
            promotedCount: promotedCount,
            failedMoveCount: failedMoveCount
        )
    }

    private static func plan(
        entry: PendingLedger.PendingEntry,
        items: [MenuBarItem],
        controlItems: MenuBarControlItems,
        hiddenBounds: CGRect,
        boundsForWindowID: [CGWindowID: CGRect],
        planningInput: PendingLedger.RelocationPlanningInput
    ) -> PendingLedger.PendingMove {
        PendingLedger.planPendingMove(
            entry: entry,
            items: items,
            controlItems: controlItems,
            hiddenBounds: hiddenBounds,
            boundsForWindowID: boundsForWindowID,
            activelyShownTags: planningInput.activelyShownTags,
            returnInfo: planningInput.returnInfo
        )
    }

    private static func item(
        matching tagIdentifier: String,
        in items: [MenuBarItem]
    ) -> MenuBarItem? {
        items.first { item in
            item.tag.tagIdentifier == tagIdentifier
        }
    }
}
