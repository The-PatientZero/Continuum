//
//  MenuBarSavedLayoutSequencePolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure sequence builder for saved-layout apply.
///
/// The manager captures a one-time section snapshot from WindowServer. This
/// policy turns that snapshot plus the saved layout into deterministic current
/// and desired sequences, keeping the planner independent from live re-queries.
enum MenuBarSavedLayoutSequencePolicy {
    struct ItemObservation: Equatable {
        let uniqueIdentifier: String
        let currentSection: MenuBarSection.Name?
        let isLayoutItem: Bool
    }

    struct CurrentSnapshot: Equatable {
        let currentFlat: [String]
        let sectionUIDs: [MenuBarSection.Name: [String]]
    }

    struct Plan: Equatable {
        let currentSnapshot: CurrentSnapshot
        let desiredFlat: [String]
        let desiredFiltered: [String]
        let sectionMap: [String: String]

        var currentFlat: [String] {
            currentSnapshot.currentFlat
        }

        var sectionUIDs: [MenuBarSection.Name: [String]] {
            currentSnapshot.sectionUIDs
        }
    }

    static func sectionSnapshot(
        items: [MenuBarItem],
        isLayoutItem: (MenuBarItem) -> Bool,
        sectionForItem: (MenuBarItem) -> MenuBarSection.Name?
    ) -> [CGWindowID: MenuBarSection.Name] {
        var sections = [CGWindowID: MenuBarSection.Name]()
        for item in items where isLayoutItem(item) {
            if let section = sectionForItem(item) {
                sections[item.windowID] = section
            }
        }
        return sections
    }

    static func itemObservations(
        items: [MenuBarItem],
        sectionByWindowID: [CGWindowID: MenuBarSection.Name],
        isLayoutItem: (MenuBarItem) -> Bool
    ) -> [ItemObservation] {
        items.map { item in
            ItemObservation(
                uniqueIdentifier: item.uniqueIdentifier,
                currentSection: sectionByWindowID[item.windowID],
                isLayoutItem: isLayoutItem(item)
            )
        }
    }

    static func plan(
        items: [ItemObservation],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]],
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?
    ) -> Plan {
        let desired = desiredSequence(
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder,
            hiddenControlUID: hiddenControlUID,
            alwaysHiddenControlUID: alwaysHiddenControlUID
        )
        let current = currentSnapshot(
            items: items,
            hiddenControlUID: hiddenControlUID,
            alwaysHiddenControlUID: alwaysHiddenControlUID
        )
        let currentSet = Set(current.currentFlat)
        return Plan(
            currentSnapshot: current,
            desiredFlat: desired.flat,
            desiredFiltered: desired.flat.filter { currentSet.contains($0) },
            sectionMap: desired.sectionMap
        )
    }

    static func currentSnapshot(
        items: [ItemObservation],
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?
    ) -> CurrentSnapshot {
        var sectionUIDs = [MenuBarSection.Name: [String]]()
        for section in sections {
            sectionUIDs[section] = items.compactMap { item in
                guard item.isLayoutItem,
                      item.currentSection == section,
                      item.uniqueIdentifier != hiddenControlUID
                else {
                    return nil
                }
                if let alwaysHiddenControlUID,
                   item.uniqueIdentifier == alwaysHiddenControlUID
                {
                    return nil
                }
                return item.uniqueIdentifier
            }
        }

        return CurrentSnapshot(
            currentFlat: LayoutSolver.flattenCurrentSections(
                visible: sectionUIDs[.visible] ?? [],
                hidden: sectionUIDs[.hidden] ?? [],
                alwaysHidden: sectionUIDs[.alwaysHidden] ?? [],
                hiddenCtrlUID: hiddenControlUID,
                ahCtrlUID: alwaysHiddenControlUID
            ),
            sectionUIDs: sectionUIDs
        )
    }

    private static func desiredSequence(
        itemSectionMap: [String: String],
        itemOrder: [String: [String]],
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?
    ) -> (flat: [String], sectionMap: [String: String]) {
        var sectionMap = itemSectionMap
        var flat = [String]()

        flat.append(contentsOf: itemOrder[MenuBarSection.Name.visible.rawValue] ?? [])
        flat.append(hiddenControlUID)
        sectionMap[hiddenControlUID] = MenuBarSection.Name.hidden.rawValue
        flat.append(contentsOf: itemOrder[MenuBarSection.Name.hidden.rawValue] ?? [])

        if let alwaysHiddenControlUID {
            flat.append(alwaysHiddenControlUID)
            sectionMap[alwaysHiddenControlUID] = MenuBarSection.Name.alwaysHidden.rawValue
        }
        flat.append(contentsOf: itemOrder[MenuBarSection.Name.alwaysHidden.rawValue] ?? [])

        return (flat, sectionMap)
    }

    private static let sections: [MenuBarSection.Name] = [
        .visible,
        .hidden,
        .alwaysHidden,
    ]
}
