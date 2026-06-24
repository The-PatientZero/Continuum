//
//  MenuBarItemCache.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Runtime cache for menu bar items grouped by Continuum section.
///
/// The cache is the product's lightweight, in-memory model of the active menu
/// bar. Keeping it outside `MenuBarItemManager` lets snapshots, diagnostics,
/// saved-order persistence, layout planning, and UI drag/drop consume the same
/// data model without depending on the manager's large orchestration surface.
struct MenuBarItemCache: Hashable {
    /// Storage for cached menu bar items, keyed by section.
    private var storage = [MenuBarSection.Name: [MenuBarItem]]()

    /// The identifier of the display with the active menu bar at
    /// the time this cache was created.
    let displayID: CGDirectDisplayID?

    /// The cached menu bar items as an array.
    var managedItems: [MenuBarItem] {
        MenuBarSection.Name.allCases.reduce(into: []) { result, section in
            guard let items = storage[section] else {
                return
            }
            result.append(contentsOf: items)
        }
    }

    /// Creates a cache with the given display identifier.
    init(displayID: CGDirectDisplayID?) {
        self.displayID = displayID
    }

    /// Returns the managed menu bar items for the given section.
    func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] {
        self[section]
    }

    /// Returns the address for the menu bar item with the given tag,
    /// if it exists in the cache.
    func address(for tag: MenuBarItemTag) -> (section: MenuBarSection.Name, index: Int)? {
        for (section, items) in storage {
            guard let index = items.firstIndex(matching: tag) else {
                continue
            }
            return (section, index)
        }
        return nil
    }

    /// Inserts the given menu bar item into the cache at the specified
    /// destination.
    mutating func insert(_ item: MenuBarItem, at destination: MenuBarMoveDestination) {
        let targetTag = destination.targetItem.tag

        if targetTag == .hiddenControlItem {
            if destination.isLeftOfTarget {
                self[.hidden].append(item)
            } else {
                self[.visible].insert(item, at: 0)
            }
            return
        }

        if targetTag == .alwaysHiddenControlItem {
            if destination.isLeftOfTarget {
                self[.alwaysHidden].append(item)
            } else {
                self[.hidden].insert(item, at: 0)
            }
            return
        }

        guard case (let section, var index)? = address(for: targetTag) else {
            return
        }

        if destination.isRightOfTarget {
            let range = self[section].startIndex ... self[section].endIndex
            index = (index + 1).clamped(to: range)
        }

        self[section].insert(item, at: index)
    }

    /// Accesses the items in the given section.
    subscript(section: MenuBarSection.Name) -> [MenuBarItem] {
        get { storage[section, default: []] }
        set { storage[section] = newValue }
    }
}
