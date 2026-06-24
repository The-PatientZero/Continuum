//
//  MenuBarSavedLayoutPlannedMoveExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Executes one saved-layout planned-move batch against fresh menu-bar observations.
///
/// Saved-layout LCS phases resolve abstract planned destinations against live
/// WindowServer state before every move, because previous moves can shift item
/// positions. This executor owns that repeated observe-resolve-move-pace loop
/// while callers keep ownership of live observation, diagnostics, and CGEvent
/// posting.
enum MenuBarSavedLayoutPlannedMoveExecutor {
    enum StopReason: Equatable {
        case completed
        case cancelled
        case observationUnavailable
        case controlItemsMissing
    }

    struct Outcome: Equatable {
        let movedCount: Int
        let stopReason: StopReason

        var needsDeferredCacheRefresh: Bool {
            stopReason == .observationUnavailable
        }
    }

    @MainActor
    static func execute(
        plannedMoves: [LayoutSolver.LCSPlannedMove],
        controlItemWindowIDs: MenuBarControlItemWindowIDs,
        sectionMap: [String: String],
        observationContext: String,
        phase: MenuBarSavedLayoutExecutionPolicy.Phase,
        observeItems: (String) async -> [MenuBarItem]?,
        moveItem: (MenuBarItem, MenuBarMoveDestination) async throws -> Void,
        recordMoveFailure: (String, Error) -> Void,
        sleepAfterMove: (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> Outcome {
        var movedCount = 0

        for planned in plannedMoves {
            guard !Task.isCancelled else {
                return Outcome(movedCount: movedCount, stopReason: .cancelled)
            }

            guard let allFreshItems = await observeItems(observationContext) else {
                return Outcome(movedCount: movedCount, stopReason: .observationUnavailable)
            }
            var freshItemsCopy = allFreshItems
            guard let freshControl = MenuBarControlItems(
                items: &freshItemsCopy,
                windowIDs: controlItemWindowIDs
            ) else {
                return Outcome(movedCount: movedCount, stopReason: .controlItemsMissing)
            }

            let resolution = MenuBarSavedLayoutExecutionPolicy.plannedMoveResolution(
                planned: planned,
                items: allFreshItems,
                controlItems: freshControl,
                fallbackSection: fallbackSection(for: planned, sectionMap: sectionMap),
                isLayoutItem: MenuBarSavedLayoutItemPolicy.isLayoutItem
            )

            let resolvedMove: MenuBarSavedLayoutExecutionPolicy.ResolvedMove
            switch resolution {
            case let .move(move):
                resolvedMove = move
            case .itemMissing:
                continue
            }

            do {
                try await moveItem(resolvedMove.item, resolvedMove.destination)
                movedCount += 1
                await sleepAfterMove(MenuBarSavedLayoutExecutionPolicy.delay(after: phase))
            } catch {
                recordMoveFailure(planned.uid, error)
            }
        }

        return Outcome(movedCount: movedCount, stopReason: .completed)
    }

    private static func fallbackSection(
        for planned: LayoutSolver.LCSPlannedMove,
        sectionMap: [String: String]
    ) -> MenuBarSection.Name {
        guard let sectionKey = sectionMap[planned.uid],
              let section = MenuBarSection.Name(rawValue: sectionKey)
        else {
            return .visible
        }
        return section
    }
}
