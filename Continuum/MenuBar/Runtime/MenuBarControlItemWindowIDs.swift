//
//  MenuBarControlItemWindowIDs.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Known WindowServer IDs for Continuum's menu bar section control items.
///
/// The visible, hidden, and always-hidden dividers can be reported with stale
/// tags by the WindowServer. Passing the IDs as one value keeps every cache,
/// reset, restore, and saved-layout path on the same discovery contract.
struct MenuBarControlItemWindowIDs: Equatable {
    static let unresolved = MenuBarControlItemWindowIDs()

    let visible: CGWindowID?
    let hidden: CGWindowID?
    let alwaysHidden: CGWindowID?

    init(
        visible: CGWindowID? = nil,
        hidden: CGWindowID? = nil,
        alwaysHidden: CGWindowID? = nil
    ) {
        self.visible = visible
        self.hidden = hidden
        self.alwaysHidden = alwaysHidden
    }
}
