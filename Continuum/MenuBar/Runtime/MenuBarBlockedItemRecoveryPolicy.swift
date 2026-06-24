//
//  MenuBarBlockedItemRecoveryPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure policy for selecting menu bar items that are safe to recover from
/// macOS's blocked x=-1 position.
///
/// Observation and movement stay in the manager; this policy only decides
/// whether a live item is a recoverable user item and which structural anchor
/// restores it to the visible side of the hidden divider.
enum MenuBarBlockedItemRecoveryPolicy {
    static func recoveryCandidates(
        from items: [MenuBarItem],
        currentBoundsForItem: (MenuBarItem) -> CGRect?
    ) -> [MenuBarItem] {
        items.filter { item in
            guard item.isMovable, !item.isControlItem else {
                return false
            }

            let bounds = currentBoundsForItem(item) ?? item.bounds
            return MenuBarCacheCommitPolicy.isBlockedWindowBounds(bounds)
        }
    }

    static func visibleRecoveryDestination(
        hiddenControlItem: MenuBarItem
    ) -> MenuBarMoveDestination {
        .rightOfItem(hiddenControlItem)
    }
}
