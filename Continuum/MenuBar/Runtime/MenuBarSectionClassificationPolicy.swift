//
//  MenuBarSectionClassificationPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure policy for deciding whether an observed menu bar item belongs in the
/// runtime cache and which section its current bounds occupy.
///
/// The manager owns Window Server lookups and cache mutation. This policy owns
/// the deterministic section model used by snapshots and planners.
enum MenuBarSectionClassificationPolicy {
    static func isCacheable(_ item: MenuBarItem) -> Bool {
        if item.tag == .visibleControlItem {
            return true
        }
        if !item.canBeHidden {
            return false
        }
        if item.isSystemClone {
            return false
        }
        if item.isContinuumStructuralItem {
            return item.tag == .visibleControlItem
        }
        if item.isControlItem, item.tag != .visibleControlItem {
            return false
        }
        return true
    }

    static func section(
        for itemBounds: CGRect,
        hiddenControlItemBounds: CGRect,
        alwaysHiddenControlItemBounds: CGRect?
    ) -> MenuBarSection.Name {
        if itemBounds.minX >= hiddenControlItemBounds.maxX {
            return .visible
        }
        if itemBounds.maxX <= hiddenControlItemBounds.minX {
            if let alwaysHiddenControlItemBounds {
                if itemBounds.minX >= alwaysHiddenControlItemBounds.maxX {
                    return .hidden
                }
                if itemBounds.maxX <= alwaysHiddenControlItemBounds.minX {
                    return .alwaysHidden
                }
            } else {
                return .hidden
            }
        }

        let itemMidpoint = (itemBounds.minX + itemBounds.maxX) / 2
        let hiddenMidpoint = (hiddenControlItemBounds.minX + hiddenControlItemBounds.maxX) / 2
        if itemMidpoint >= hiddenMidpoint {
            return .visible
        }
        if let alwaysHiddenControlItemBounds {
            let alwaysHiddenMidpoint = (
                alwaysHiddenControlItemBounds.minX + alwaysHiddenControlItemBounds.maxX
            ) / 2
            return itemMidpoint >= alwaysHiddenMidpoint ? .hidden : .alwaysHidden
        }
        return .hidden
    }
}
