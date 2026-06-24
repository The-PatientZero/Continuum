//
//  MenuBarRuntimeInventory.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Read-only inventory returned by the menu bar runtime control plane.
struct MenuBarRuntimeInventory: Equatable {
    let generatedAt: Date
    let state: MenuBarRuntimeState
    let snapshot: MenuBarSnapshot

    var allItems: [MenuBarSnapshotItem] {
        snapshot.items
    }

    var shownItems: [MenuBarSnapshotItem] {
        items(in: .visible)
    }

    var hiddenItems: [MenuBarSnapshotItem] {
        items(in: .hidden)
    }

    var alwaysHiddenItems: [MenuBarSnapshotItem] {
        items(in: .alwaysHidden)
    }

    var isActionable: Bool {
        snapshot.isActionable && state != .recovering && !isDegraded
    }

    var isDegraded: Bool {
        if case .degraded = state {
            return true
        }
        return false
    }

    var recommendedRecoveryAction: MenuBarRuntimeRecoveryAction {
        MenuBarRecoveryPolicy.recommendedAction(
            state: state,
            snapshot: snapshot
        )
    }

    init(
        generatedAt: Date = Date(),
        state: MenuBarRuntimeState,
        snapshot: MenuBarSnapshot
    ) {
        self.generatedAt = generatedAt
        self.state = state
        self.snapshot = snapshot
    }

    func items(in section: MenuBarSection.Name) -> [MenuBarSnapshotItem] {
        snapshot.itemsBySection[section, default: []]
    }

    func item(withIdentifier identifier: String) -> MenuBarSnapshotItem? {
        allItems.first { $0.itemIdentifier == identifier }
    }
}

extension MenuBarItemManager {
    /// Returns the latest read-only menu bar inventory.
    ///
    /// This is the local equivalent of Barbee's inspect-first flow: callers get
    /// exact item identifiers and confidence before attempting any mutation.
    func currentRuntimeInventory(generatedAt: Date = Date()) -> MenuBarRuntimeInventory {
        let snapshot = latestRuntimeSnapshot ?? MenuBarSnapshot(
            cache: itemCache,
            controlItemsMissing: areControlItemsMissing,
            systemMenuBarHidden: appState?.menuBarManager.isMenuBarHiddenBySystem == true ||
                appState?.menuBarManager.isMenuBarHiddenBySystemUserDefaults == true,
            createdAt: generatedAt
        )
        return MenuBarRuntimeInventory(
            generatedAt: generatedAt,
            state: runtimeState,
            snapshot: snapshot
        )
    }
}
