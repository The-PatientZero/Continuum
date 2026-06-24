//
//  MenuBarSavedLayoutExecutionPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Runtime policy for saved-layout apply execution.
///
/// Saved-layout apply is the most expensive path in the menu bar runtime: it
/// repeatedly observes WindowServer state and posts synthetic move events.
/// Keep strategy selection and pacing in one pure policy so stability tuning
/// does not live as scattered magic delays inside MenuBarItemManager.
enum MenuBarSavedLayoutExecutionPolicy {
    enum Strategy: Equatable {
        case fullSort
        case lcs
    }

    enum InitialPlan: Equatable {
        case alreadyMatches
        case fullSort(sequence: [String])
        case lcs
    }

    struct SectionObservation: Equatable {
        let uniqueIdentifier: String
        let currentSection: MenuBarSection.Name?
        let isLayoutItem: Bool
    }

    struct ResolvedMove: Equatable {
        let item: MenuBarItem
        let destination: MenuBarMoveDestination
    }

    enum FullSortMoveResolution: Equatable {
        case move(ResolvedMove)
        case itemMissing
        case controlCenterMissing
    }

    enum PlannedMoveResolution: Equatable {
        case move(ResolvedMove)
        case itemMissing
    }

    enum Phase: Equatable {
        case fullSortMove
        case fullSortSettle
        case controlExpansionSettle
        case visibleBoundaryMove
        case controlBoundaryMove
        case crossSectionFallbackMove
        case lcsMove
    }

    static func strategy(
        displayHasNotch: Bool,
        useLCSOnNotchedDisplay: Bool
    ) -> Strategy {
        if displayHasNotch && !useLCSOnNotchedDisplay {
            return .fullSort
        }
        return .lcs
    }

    static func initialPlan(
        currentFlat: [String],
        desiredFiltered: [String],
        sectionMap: [String: String],
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?,
        strategy: Strategy
    ) -> InitialPlan {
        let desiredSet = Set(desiredFiltered)
        let currentRelevantFlat = currentFlat.filter { desiredSet.contains($0) }
        if currentRelevantFlat == desiredFiltered {
            return .alreadyMatches
        }

        switch strategy {
        case .fullSort:
            return .fullSort(
                sequence: LayoutSolver.planFullSortSequence(
                    currentFlat: currentFlat,
                    desiredFiltered: desiredFiltered,
                    sectionMap: sectionMap,
                    hiddenCtrlUID: hiddenControlUID,
                    ahCtrlUID: alwaysHiddenControlUID
                )
            )
        case .lcs:
            return .lcs
        }
    }

    static func visibleBoundaryMovePlan(
        items: [SectionObservation],
        desiredFiltered: [String],
        sectionMap: [String: String],
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?
    ) -> [LayoutSolver.LCSPlannedMove] {
        var currentSectionByUID = [String: MenuBarSection.Name]()
        for item in items where item.isLayoutItem {
            if let section = item.currentSection {
                currentSectionByUID[item.uniqueIdentifier] = section
            }
        }

        var desiredSectionByUID = [String: MenuBarSection.Name]()
        for (identifier, sectionKey) in sectionMap {
            guard let section = sectionName(for: sectionKey) else {
                continue
            }
            desiredSectionByUID[identifier] = section
        }

        let desiredOrder = desiredFiltered.filter {
            $0 != hiddenControlUID && $0 != alwaysHiddenControlUID
        }
        return LayoutSolver.planVisibleBoundaryMoves(
            currentSectionByUID: currentSectionByUID,
            desiredSectionByUID: desiredSectionByUID,
            desiredOrder: desiredOrder
        )
    }

    static func lcsMovePlan(
        currentFlat: [String],
        desiredFiltered: [String],
        sectionMap: [String: String],
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?
    ) -> [LayoutSolver.LCSPlannedMove] {
        let currentNoControls = currentFlat.filter {
            $0 != hiddenControlUID && $0 != alwaysHiddenControlUID
        }
        let desiredNoControls = desiredFiltered.filter {
            $0 != hiddenControlUID && $0 != alwaysHiddenControlUID
        }
        return LayoutSolver.planLCSMoveSequence(
            currentNoControls: currentNoControls,
            desiredNoControls: desiredNoControls,
            sectionMap: sectionMap
        )
    }

    static func fullSortMoveResolution(
        uid: String,
        items: [MenuBarItem],
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?,
        isLayoutItem: (MenuBarItem) -> Bool
    ) -> FullSortMoveResolution {
        let isControlUID = uid == hiddenControlUID || uid == alwaysHiddenControlUID
        guard let item = items.first(where: {
            if isControlUID { return $0.uniqueIdentifier == uid }
            return $0.uniqueIdentifier == uid && isLayoutItem($0)
        }) else {
            return .itemMissing
        }

        guard let controlCenter = items.first(where: { $0.tag == .controlCenter }) else {
            return .controlCenterMissing
        }

        return .move(
            ResolvedMove(
                item: item,
                destination: .leftOfItem(controlCenter)
            )
        )
    }

    static func plannedMoveResolution(
        planned: LayoutSolver.LCSPlannedMove,
        items: [MenuBarItem],
        controlItems: MenuBarControlItems,
        fallbackSection: MenuBarSection.Name,
        isLayoutItem: (MenuBarItem) -> Bool
    ) -> PlannedMoveResolution {
        guard let item = items.first(where: {
            $0.uniqueIdentifier == planned.uid && isLayoutItem($0)
        }) else {
            return .itemMissing
        }

        let destination = LayoutReconciler.resolveDestination(
            planned.destination,
            items: items,
            controlItems: controlItems,
            fallbackSection: fallbackSection
        )

        return .move(
            ResolvedMove(
                item: item,
                destination: destination
            )
        )
    }

    static func delay(after phase: Phase) -> Duration {
        switch phase {
        case .fullSortMove, .fullSortSettle, .controlExpansionSettle:
            return .milliseconds(200)
        case .visibleBoundaryMove:
            return .milliseconds(150)
        case .controlBoundaryMove, .lcsMove:
            return .milliseconds(200)
        case .crossSectionFallbackMove:
            return .milliseconds(100)
        }
    }

    private static func sectionName(for sectionKey: String) -> MenuBarSection.Name? {
        switch sectionKey {
        case "visible":
            .visible
        case "hidden":
            .hidden
        case "alwaysHidden":
            .alwaysHidden
        default:
            nil
        }
    }
}
