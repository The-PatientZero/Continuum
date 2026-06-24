//
//  MenuBarControlItemDiscoveryPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Pure heuristics for recognizing Continuum-owned control items from noisy
/// WindowServer observations.
enum MenuBarControlItemDiscoveryPolicy {
    static let visibleFallbackMaximumWidth: CGFloat = 100
    static let wideDividerMinimumWidth: CGFloat = 1_000

    static func shouldReclassifyKnownControlItem(
        _ item: MenuBarItem,
        as tag: MenuBarItemTag,
        title: String,
        processID: pid_t
    ) -> Bool {
        item.tag != tag || item.sourcePID != processID || item.title != title
    }

    static func isVisibleControlItemFallback(_ item: MenuBarItem) -> Bool {
        !item.isControlItem &&
            item.isContinuumStructuralItem &&
            item.bounds.width <= visibleFallbackMaximumWidth
    }

    static func wideDividerIndices(in items: [MenuBarItem]) -> [Int] {
        items.indices
            .filter { items[$0].bounds.width >= wideDividerMinimumWidth }
            .sorted { items[$0].bounds.minX > items[$1].bounds.minX }
    }

    static func adjustedIndexAfterRemoving(_ index: Int, removedIndex: Int) -> Int {
        index > removedIndex ? index - 1 : index
    }
}
