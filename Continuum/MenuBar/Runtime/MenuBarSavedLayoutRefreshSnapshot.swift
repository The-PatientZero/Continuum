//
//  MenuBarSavedLayoutRefreshSnapshot.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Normalized live observation captured after saved-layout move phases.
///
/// Move phases can shift divider positions and WindowServer can re-emit
/// Continuum control items with updated windows. Rebuilding this snapshot from
/// the fresh observation keeps later planning phases off stale section
/// boundaries while still exposing only the lightweight current-state inputs
/// they need.
struct MenuBarSavedLayoutRefreshSnapshot {
    let items: [MenuBarItem]
    let controlItems: MenuBarControlItems
    let sectionByWindowID: [CGWindowID: MenuBarSection.Name]
    let currentFlat: [String]

    init?(
        observedItems: [MenuBarItem],
        controlItemWindowIDs: MenuBarControlItemWindowIDs,
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?,
        makeSectionLookupContext: (MenuBarControlItems) -> MenuBarSectionLookupContext
    ) {
        var normalizedItems = observedItems
        guard let controlItems = MenuBarControlItems(
            items: &normalizedItems,
            windowIDs: controlItemWindowIDs
        ) else {
            return nil
        }

        let context = makeSectionLookupContext(controlItems)
        let sectionByWindowID = MenuBarSavedLayoutSequencePolicy.sectionSnapshot(
            items: normalizedItems,
            isLayoutItem: MenuBarSavedLayoutItemPolicy.isLayoutItem
        ) { item in
            context.findSection(for: item)
        }
        let currentSnapshot = MenuBarSavedLayoutSequencePolicy.currentSnapshot(
            items: MenuBarSavedLayoutSequencePolicy.itemObservations(
                items: normalizedItems,
                sectionByWindowID: sectionByWindowID,
                isLayoutItem: MenuBarSavedLayoutItemPolicy.isLayoutItem
            ),
            hiddenControlUID: hiddenControlUID,
            alwaysHiddenControlUID: alwaysHiddenControlUID
        )

        self.items = normalizedItems
        self.controlItems = controlItems
        self.sectionByWindowID = sectionByWindowID
        self.currentFlat = currentSnapshot.currentFlat
    }
}
