//
//  MenuBarSavedLayoutItemPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Policy for deciding which observed items participate in saved-layout apply.
///
/// Saved-layout apply is allowed to move user-manageable status items.
/// Structural Continuum controls and immovable/non-hideable system items must
/// stay out of the planner so retries remain bounded under menu-bar churn.
enum MenuBarSavedLayoutItemPolicy {
    static func isLayoutItem(_ item: MenuBarItem) -> Bool {
        (item.canBeHidden || item.tag == .visibleControlItem) &&
            item.isMovable &&
            !item.isContinuumStructuralItem
    }
}
