//
//  MenuBarControlItems.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Resolved Continuum section control items from one live menu bar observation.
///
/// These dividers define the visible, hidden, and always-hidden section
/// boundaries. Keeping the value outside the manager lets cache, reset, restore,
/// and saved-layout runtimes share one explicit control-item contract.
struct MenuBarControlItems {
    let hidden: MenuBarItem
    let alwaysHidden: MenuBarItem?

    /// Creates a control item pair from already-known control items.
    ///
    /// Used by test fixtures and by callers that have already resolved the
    /// hidden and always-hidden items themselves. Production discovery from
    /// a live menu bar uses the failable initializer below.
    init(hidden: MenuBarItem, alwaysHidden: MenuBarItem?) {
        self.hidden = hidden
        self.alwaysHidden = alwaysHidden
    }

    /// Creates a control item pair from a list of menu bar items.
    ///
    /// The initializer first attempts a tag-based lookup (namespace + title).
    /// If that fails it falls back to matching by the current process PID and
    /// known control-item titles, matching by known window IDs, and finally
    /// matching by wide divider geometry.
    ///
    /// On macOS 26 (Tahoe), all menu bar item windows are owned by Control
    /// Center and the item title reported by `kCGWindowName` may differ from
    /// the `NSStatusItem` autosaveName used to build the expected tag, so the
    /// primary lookup can fail.
    init?(
        items: inout [MenuBarItem],
        visibleControlItemWindowID: CGWindowID? = nil,
        hiddenControlItemWindowID: CGWindowID? = nil,
        alwaysHiddenControlItemWindowID: CGWindowID? = nil
    ) {
        self.init(
            items: &items,
            windowIDs: MenuBarControlItemWindowIDs(
                visible: visibleControlItemWindowID,
                hidden: hiddenControlItemWindowID,
                alwaysHidden: alwaysHiddenControlItemWindowID
            )
        )
    }

    init?(
        items: inout [MenuBarItem],
        windowIDs: MenuBarControlItemWindowIDs
    ) {
        guard let resolved = MenuBarControlItemResolver.resolve(
            items: &items,
            windowIDs: windowIDs
        ) else {
            return nil
        }
        self = resolved
    }
}
