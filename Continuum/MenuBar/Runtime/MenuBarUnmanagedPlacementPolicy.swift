//
//  MenuBarUnmanagedPlacementPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin

/// Pure saved-layout policy for items present in the live menu bar but absent
/// from the exact desired sequence.
///
/// The manager owns observations and move execution. This policy owns the
/// unstable-item exclusions and the placement application that turns saved
/// layout intent plus NewItemsPlacement into a deterministic desired sequence.
enum MenuBarUnmanagedPlacementPolicy {
    struct ItemObservation: Equatable {
        let uniqueIdentifier: String
        let tag: MenuBarItemTag
        let sourcePID: pid_t?
    }

    struct Plan: Equatable {
        let visibleControlUID: String?
        let unresolvedGenericControlCenterUIDs: Set<String>
        let unmanagedUIDs: [String]
        let placements: [String: LayoutSolver.UnmanagedPlacement]
        let desiredFiltered: [String]
        let sectionMap: [String: String]

        var hasUnmanagedItems: Bool {
            !unmanagedUIDs.isEmpty
        }

        func placementSummary(for uid: String) -> String {
            switch placements[uid] {
            case let .saved(section, index)?:
                "saved(section=\(section.logString), index=\(index))"
            case let .newItemAnchored(section, anchorUID, relation)?:
                "newItemAnchored(section=\(section.logString), anchor=\(anchorUID), relation=\(relation))"
            case let .newItemDefault(section)?:
                "newItemDefault(section=\(section.logString))"
            case nil:
                "<no placement returned>"
            }
        }
    }

    static func plan(
        items: [ItemObservation],
        currentFlat: [String],
        desiredFiltered: [String],
        sectionMap: [String: String],
        savedSectionOrder: [String: [String]],
        newItemsPlacement: MenuBarNewItemsPlacement,
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?
    ) -> Plan {
        let visibleControlUID = items
            .first(where: { $0.tag == .visibleControlItem })?
            .uniqueIdentifier
        let unresolvedGenericControlCenterUIDs = Set(
            items
                .filter { $0.tag.isControlCenterGenericItem && $0.sourcePID == nil }
                .map(\.uniqueIdentifier)
        )
        let unmanagedUIDs = LayoutSolver.partitionUnmanagedUIDs(
            currentFlat: currentFlat,
            desiredUIDs: Set(desiredFiltered),
            hiddenCtrlUID: hiddenControlUID,
            ahCtrlUID: alwaysHiddenControlUID,
            visibleCtrlUID: visibleControlUID,
            unresolvedGenericCCUIDs: unresolvedGenericControlCenterUIDs
        )

        guard !unmanagedUIDs.isEmpty else {
            return Plan(
                visibleControlUID: visibleControlUID,
                unresolvedGenericControlCenterUIDs: unresolvedGenericControlCenterUIDs,
                unmanagedUIDs: [],
                placements: [:],
                desiredFiltered: desiredFiltered,
                sectionMap: sectionMap
            )
        }

        let desiredForUnmanaged = DesiredLayout.fromSavedSectionOrder(
            savedSectionOrder,
            newItemsPlacement: newItemsPlacement
        )
        let placements = LayoutReconciler.unmanagedPlacementPlan(
            desired: desiredForUnmanaged,
            unmanagedUIDs: unmanagedUIDs,
            currentUIDs: Set(currentFlat)
        )
        let applied = LayoutReconciler.applyUnmanagedPlacementsToDesired(
            placements: placements,
            unmanagedUIDs: unmanagedUIDs,
            desiredFiltered: desiredFiltered,
            sectionMap: sectionMap,
            savedSectionOrder: savedSectionOrder,
            controlUIDs: ControlUIDs(
                visible: visibleControlUID,
                hidden: hiddenControlUID,
                alwaysHidden: alwaysHiddenControlUID
            )
        )

        return Plan(
            visibleControlUID: visibleControlUID,
            unresolvedGenericControlCenterUIDs: unresolvedGenericControlCenterUIDs,
            unmanagedUIDs: unmanagedUIDs,
            placements: placements,
            desiredFiltered: applied.desiredFiltered,
            sectionMap: applied.sectionMap
        )
    }
}
