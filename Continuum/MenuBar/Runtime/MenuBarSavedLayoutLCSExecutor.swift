//
//  MenuBarSavedLayoutLCSExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Executes the non-notched saved-layout LCS path against fresh observations.
///
/// The LCS path has three runtime phases: visible/tray boundary moves,
/// hidden/always-hidden boundary repair, and remaining item-order moves. Keeping
/// the sequencing here makes the manager an edge adapter for observation,
/// movement, and diagnostics rather than the owner of retry/rebuild policy.
enum MenuBarSavedLayoutLCSExecutor {
    enum StopReason: Equatable {
        case completed
        case cancelled
        case observationUnavailable
        case controlItemsMissing
    }

    struct Outcome: Equatable {
        let movedCount: Int
        let plannedItemMoveCount: Int
        let stopReason: StopReason

        var needsDeferredCacheRefresh: Bool {
            switch stopReason {
            case .observationUnavailable, .controlItemsMissing:
                true
            case .completed, .cancelled:
                false
            }
        }
    }

    @MainActor
    static func execute(
        currentFlat initialCurrentFlat: [String],
        items initialItems: [MenuBarItem],
        sectionByWindowID initialSectionByWindowID: [CGWindowID: MenuBarSection.Name],
        desiredFiltered: [String],
        sectionMap: [String: String],
        itemOrder: [String: [String]],
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?,
        controlItemWindowIDs: MenuBarControlItemWindowIDs,
        observeItems: (String) async -> [MenuBarItem]?,
        makeSectionLookupContext: (MenuBarControlItems) -> MenuBarSectionLookupContext,
        moveItem: (MenuBarItem, MenuBarMoveDestination) async throws -> Void,
        recordVisibleBoundaryMovesNeeded: (Int) -> Void = { _ in },
        recordVisibleBoundaryMoveFailure: (String, Error) -> Void = { _, _ in },
        recordRefreshControlItemsMissing: (String) -> Void = { _ in },
        recordTransitionAssessment: (MenuBarSectionTransitionPolicy.Assessment) -> Void = { _ in },
        recordTransitionControlMoveNeeded: (MenuBarSectionTransitionPolicy.Assessment) -> Void = { _ in },
        recordControlMoveStart: (MenuBarMoveDestination) -> Void = { _ in },
        recordControlMoveFailure: (Error) -> Void = { _ in },
        recordFallbackPlan: (MenuBarSectionTransitionPolicy.FallbackPlan) -> Void = { _ in },
        recordFallbackMoveFailure: (MenuBarSectionTransitionPolicy.FallbackMove, Error) -> Void = { _, _ in },
        recordNoItemReorderingNeeded: (Int) -> Void = { _ in },
        recordItemMovesNeeded: (Int, Int) -> Void = { _, _ in },
        recordLCSMoveFailure: (String, Error) -> Void = { _, _ in },
        recordCompletion: (Int) -> Void = { _ in }
    ) async -> Outcome {
        var items = initialItems
        var sectionByWindowID = initialSectionByWindowID
        var currentFlat = initialCurrentFlat
        var movedCount = 0

        let visibleBoundaryMoves = MenuBarSavedLayoutExecutionPolicy.visibleBoundaryMovePlan(
            items: sectionObservations(items: items, sectionByWindowID: sectionByWindowID),
            desiredFiltered: desiredFiltered,
            sectionMap: sectionMap,
            hiddenControlUID: hiddenControlUID,
            alwaysHiddenControlUID: alwaysHiddenControlUID
        )

        if !visibleBoundaryMoves.isEmpty {
            recordVisibleBoundaryMovesNeeded(visibleBoundaryMoves.count)
        }

        let visibleBoundaryOutcome = await MenuBarSavedLayoutPlannedMoveExecutor.execute(
            plannedMoves: visibleBoundaryMoves,
            controlItemWindowIDs: controlItemWindowIDs,
            sectionMap: sectionMap,
            observationContext: "visibleBoundaryMove",
            phase: .visibleBoundaryMove,
            observeItems: observeItems,
            moveItem: moveItem,
            recordMoveFailure: recordVisibleBoundaryMoveFailure
        )
        movedCount += visibleBoundaryOutcome.movedCount
        if let stopReason = stopReason(from: visibleBoundaryOutcome.stopReason) {
            return Outcome(
                movedCount: movedCount,
                plannedItemMoveCount: 0,
                stopReason: stopReason
            )
        }

        if movedCount > 0 {
            let refresh = await refreshedSnapshot(
                context: "afterVisibleBoundaryMoves",
                controlItemWindowIDs: controlItemWindowIDs,
                hiddenControlUID: hiddenControlUID,
                alwaysHiddenControlUID: alwaysHiddenControlUID,
                observeItems: observeItems,
                makeSectionLookupContext: makeSectionLookupContext,
                recordRefreshControlItemsMissing: recordRefreshControlItemsMissing
            )
            switch refresh {
            case let .success(snapshot):
                items = snapshot.items
                sectionByWindowID = snapshot.sectionByWindowID
            case let .failure(stopReason):
                return Outcome(
                    movedCount: movedCount,
                    plannedItemMoveCount: 0,
                    stopReason: stopReason
                )
            }
        }

        let transitionAssessment = MenuBarSectionTransitionPolicy.assess(
            MenuBarSectionTransitionPolicy.sectionSets(
                observations: items.map { item in
                    MenuBarSectionTransitionPolicy.SectionObservation(
                        uniqueIdentifier: item.uniqueIdentifier,
                        windowID: item.windowID,
                        isLayoutItem: MenuBarSavedLayoutItemPolicy.isLayoutItem(item)
                    )
                },
                sectionByWindowID: sectionByWindowID,
                itemOrder: itemOrder
            )
        )
        recordTransitionAssessment(transitionAssessment)

        if let alwaysHiddenMovePlan = MenuBarSectionTransitionPolicy.alwaysHiddenControlMovePlan(
            assessment: transitionAssessment,
            itemOrder: itemOrder,
            hiddenControlUID: hiddenControlUID,
            alwaysHiddenControlUID: alwaysHiddenControlUID
        ) {
            recordTransitionControlMoveNeeded(transitionAssessment)

            let transitionOutcome = await MenuBarSectionTransitionExecutor.execute(
                plan: alwaysHiddenMovePlan,
                itemOrder: itemOrder,
                hiddenControlUID: hiddenControlUID,
                controlItemWindowIDs: controlItemWindowIDs,
                observeItems: observeItems,
                makeSectionLookupContext: makeSectionLookupContext,
                moveItem: moveItem,
                recordControlMoveStart: recordControlMoveStart,
                recordControlMoveFailure: recordControlMoveFailure,
                recordFallbackPlan: recordFallbackPlan,
                recordFallbackMoveFailure: recordFallbackMoveFailure
            )
            movedCount += transitionOutcome.movedCount
            if let stopReason = stopReason(from: transitionOutcome.stopReason) {
                return Outcome(
                    movedCount: movedCount,
                    plannedItemMoveCount: 0,
                    stopReason: stopReason
                )
            }
        }

        if movedCount > 0 {
            let refresh = await refreshedSnapshot(
                context: "afterControlBoundaryMoves",
                controlItemWindowIDs: controlItemWindowIDs,
                hiddenControlUID: hiddenControlUID,
                alwaysHiddenControlUID: alwaysHiddenControlUID,
                observeItems: observeItems,
                makeSectionLookupContext: makeSectionLookupContext,
                recordRefreshControlItemsMissing: recordRefreshControlItemsMissing
            )
            switch refresh {
            case let .success(snapshot):
                items = snapshot.items
                sectionByWindowID = snapshot.sectionByWindowID
                currentFlat = snapshot.currentFlat
            case let .failure(stopReason):
                return Outcome(
                    movedCount: movedCount,
                    plannedItemMoveCount: 0,
                    stopReason: stopReason
                )
            }
        }

        let plannedMoves = MenuBarSavedLayoutExecutionPolicy.lcsMovePlan(
            currentFlat: currentFlat,
            desiredFiltered: desiredFiltered,
            sectionMap: sectionMap,
            hiddenControlUID: hiddenControlUID,
            alwaysHiddenControlUID: alwaysHiddenControlUID
        )

        guard !plannedMoves.isEmpty else {
            recordNoItemReorderingNeeded(movedCount)
            return Outcome(
                movedCount: movedCount,
                plannedItemMoveCount: 0,
                stopReason: .completed
            )
        }

        recordItemMovesNeeded(plannedMoves.count, movedCount)

        let lcsOutcome = await MenuBarSavedLayoutPlannedMoveExecutor.execute(
            plannedMoves: plannedMoves,
            controlItemWindowIDs: controlItemWindowIDs,
            sectionMap: sectionMap,
            observationContext: "lcsMove",
            phase: .lcsMove,
            observeItems: observeItems,
            moveItem: moveItem,
            recordMoveFailure: recordLCSMoveFailure
        )
        movedCount += lcsOutcome.movedCount
        if let stopReason = stopReason(from: lcsOutcome.stopReason) {
            return Outcome(
                movedCount: movedCount,
                plannedItemMoveCount: plannedMoves.count,
                stopReason: stopReason
            )
        }

        recordCompletion(movedCount)
        return Outcome(
            movedCount: movedCount,
            plannedItemMoveCount: plannedMoves.count,
            stopReason: .completed
        )
    }

    private enum RefreshResult {
        case success(MenuBarSavedLayoutRefreshSnapshot)
        case failure(StopReason)
    }

    @MainActor
    private static func refreshedSnapshot(
        context: String,
        controlItemWindowIDs: MenuBarControlItemWindowIDs,
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?,
        observeItems: (String) async -> [MenuBarItem]?,
        makeSectionLookupContext: (MenuBarControlItems) -> MenuBarSectionLookupContext,
        recordRefreshControlItemsMissing: (String) -> Void
    ) async -> RefreshResult {
        guard let refreshedItems = await observeItems(context) else {
            return .failure(.observationUnavailable)
        }
        guard let refreshSnapshot = MenuBarSavedLayoutRefreshSnapshot(
            observedItems: refreshedItems,
            controlItemWindowIDs: controlItemWindowIDs,
            hiddenControlUID: hiddenControlUID,
            alwaysHiddenControlUID: alwaysHiddenControlUID,
            makeSectionLookupContext: makeSectionLookupContext
        ) else {
            recordRefreshControlItemsMissing(context)
            return .failure(.controlItemsMissing)
        }
        return .success(refreshSnapshot)
    }

    private static func sectionObservations(
        items: [MenuBarItem],
        sectionByWindowID: [CGWindowID: MenuBarSection.Name]
    ) -> [MenuBarSavedLayoutExecutionPolicy.SectionObservation] {
        items.map { item in
            MenuBarSavedLayoutExecutionPolicy.SectionObservation(
                uniqueIdentifier: item.uniqueIdentifier,
                currentSection: sectionByWindowID[item.windowID],
                isLayoutItem: MenuBarSavedLayoutItemPolicy.isLayoutItem(item)
            )
        }
    }

    private static func stopReason(
        from reason: MenuBarSavedLayoutPlannedMoveExecutor.StopReason
    ) -> StopReason? {
        switch reason {
        case .completed:
            nil
        case .cancelled:
            .cancelled
        case .observationUnavailable:
            .observationUnavailable
        case .controlItemsMissing:
            .controlItemsMissing
        }
    }

    private static func stopReason(
        from reason: MenuBarSectionTransitionExecutor.StopReason
    ) -> StopReason? {
        switch reason {
        case .completed:
            nil
        case .cancelled:
            .cancelled
        case .observationUnavailable:
            .observationUnavailable
        }
    }
}
