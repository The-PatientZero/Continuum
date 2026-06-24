//
//  MenuBarSavedLayoutObservationSnapshot.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Normalized live observation used to start a saved-layout apply pass.
///
/// WindowServer observations can report Continuum control items inline with
/// user items. This value resolves those controls once, restores them to the
/// planner input explicitly, and captures section assignments before move
/// execution starts.
struct MenuBarSavedLayoutObservationSnapshot {
    let items: [MenuBarItem]
    let controlItems: MenuBarControlItems
    let sectionByWindowID: [CGWindowID: MenuBarSection.Name]
    let sequencePlan: MenuBarSavedLayoutSequencePolicy.Plan

    init?(
        observedItems: [MenuBarItem],
        controlItemWindowIDs: MenuBarControlItemWindowIDs,
        itemSectionMap: [String: String],
        itemOrder: [String: [String]],
        makeSectionLookupContext: (MenuBarControlItems) -> MenuBarSectionLookupContext
    ) {
        var normalizedItems = observedItems
        guard let controlItems = MenuBarControlItems(
            items: &normalizedItems,
            windowIDs: controlItemWindowIDs
        ) else {
            return nil
        }

        normalizedItems.append(controlItems.hidden)
        if let alwaysHidden = controlItems.alwaysHidden {
            normalizedItems.append(alwaysHidden)
        }

        let context = makeSectionLookupContext(controlItems)
        let sectionByWindowID = MenuBarSavedLayoutSequencePolicy.sectionSnapshot(
            items: normalizedItems,
            isLayoutItem: MenuBarSavedLayoutItemPolicy.isLayoutItem,
            sectionForItem: { context.findSection(for: $0) }
        )
        let sequencePlan = MenuBarSavedLayoutSequencePolicy.plan(
            items: MenuBarSavedLayoutSequencePolicy.itemObservations(
                items: normalizedItems,
                sectionByWindowID: sectionByWindowID,
                isLayoutItem: MenuBarSavedLayoutItemPolicy.isLayoutItem
            ),
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder,
            hiddenControlUID: controlItems.hidden.uniqueIdentifier,
            alwaysHiddenControlUID: controlItems.alwaysHidden?.uniqueIdentifier
        )

        self.items = normalizedItems
        self.controlItems = controlItems
        self.sectionByWindowID = sectionByWindowID
        self.sequencePlan = sequencePlan
    }
}
