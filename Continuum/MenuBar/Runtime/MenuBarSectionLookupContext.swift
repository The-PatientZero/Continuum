//
//  MenuBarSectionLookupContext.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Live section classifier for one menu bar observation.
///
/// The caller injects bounds lookup so this value can be used both in unit
/// tests and against Window Server without coupling policies to Bridging.
struct MenuBarSectionLookupContext {
    private let hiddenControlItemBounds: CGRect
    private let alwaysHiddenControlItemBounds: CGRect?
    private let currentBoundsForItem: (MenuBarItem) -> CGRect?

    init(
        controlItems: MenuBarControlItems,
        currentBoundsForItem: @escaping (MenuBarItem) -> CGRect?
    ) {
        self.currentBoundsForItem = currentBoundsForItem
        self.hiddenControlItemBounds = currentBoundsForItem(controlItems.hidden) ?? controlItems.hidden.bounds
        self.alwaysHiddenControlItemBounds = controlItems.alwaysHidden.map {
            currentBoundsForItem($0) ?? $0.bounds
        }
    }

    func findSection(for item: MenuBarItem) -> MenuBarSection.Name? {
        let itemBounds = currentBoundsForItem(item) ?? item.bounds
        return MenuBarSectionClassificationPolicy.section(
            for: itemBounds,
            hiddenControlItemBounds: hiddenControlItemBounds,
            alwaysHiddenControlItemBounds: alwaysHiddenControlItemBounds
        )
    }
}
