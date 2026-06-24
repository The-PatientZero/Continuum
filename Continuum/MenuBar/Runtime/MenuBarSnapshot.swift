//
//  MenuBarSnapshot.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Immutable item record exposed by the runtime snapshot/control plane.
///
/// This deliberately stores stable scalar values instead of live AppKit state,
/// making snapshots safe for diagnostics, verification, and tests.
struct MenuBarSnapshotItem: Hashable {
    let section: MenuBarSection.Name
    let itemIdentifier: String
    let displayName: String
    let bundleIdentifier: String?
    let windowID: CGWindowID
    let sourcePID: pid_t?
    let bounds: CGRect
    let isOnScreen: Bool
    let confidence: MenuBarIdentityConfidence

    init(section: MenuBarSection.Name, item: MenuBarItem) {
        self.section = section
        self.itemIdentifier = item.uniqueIdentifier
        self.displayName = item.displayName
        self.bundleIdentifier = item.sourceApplication?.bundleIdentifier
        self.windowID = item.windowID
        self.sourcePID = item.sourcePID
        self.bounds = item.bounds
        self.isOnScreen = item.isOnScreen
        self.confidence = item.identityConfidence
    }
}

/// A point-in-time view of Continuum's menu bar model.
struct MenuBarSnapshot: Hashable {
    let createdAt: Date
    let displayID: CGDirectDisplayID?
    let itemsBySection: [MenuBarSection.Name: [MenuBarSnapshotItem]]
    let controlItemsMissing: Bool
    let systemMenuBarHidden: Bool

    var items: [MenuBarSnapshotItem] {
        MenuBarSection.Name.allCases.flatMap { itemsBySection[$0, default: []] }
    }

    var itemCount: Int {
        items.count
    }

    var unresolvedItems: [MenuBarSnapshotItem] {
        items.filter { $0.confidence == .unresolved }
    }

    var transientItems: [MenuBarSnapshotItem] {
        items.filter { $0.confidence == .transient }
    }

    var invalidItems: [MenuBarSnapshotItem] {
        items.filter { $0.confidence == .invalid }
    }

    var blockedItems: [MenuBarSnapshotItem] {
        items.filter {
            $0.confidence.allowsAutomatedMove &&
                MenuBarCacheCommitPolicy.isBlockedWindowBounds($0.bounds)
        }
    }

    var persistableItems: [MenuBarSnapshotItem] {
        items.filter(\.confidence.allowsPersistence)
    }

    var movableItems: [MenuBarSnapshotItem] {
        items.filter(\.confidence.allowsAutomatedMove)
    }

    var isActionable: Bool {
        !controlItemsMissing && !systemMenuBarHidden && !items.isEmpty
    }

    init(
        createdAt: Date = Date(),
        displayID: CGDirectDisplayID?,
        itemsBySection: [MenuBarSection.Name: [MenuBarSnapshotItem]],
        controlItemsMissing: Bool = false,
        systemMenuBarHidden: Bool = false
    ) {
        self.createdAt = createdAt
        self.displayID = displayID
        self.itemsBySection = itemsBySection
        self.controlItemsMissing = controlItemsMissing
        self.systemMenuBarHidden = systemMenuBarHidden
    }

    init(
        cache: MenuBarItemCache,
        controlItemsMissing: Bool,
        systemMenuBarHidden: Bool,
        createdAt: Date = Date()
    ) {
        self.init(
            createdAt: createdAt,
            displayID: cache.displayID,
            itemsBySection: Dictionary(
                uniqueKeysWithValues: MenuBarSection.Name.allCases.map { section in
                    (
                        section,
                        cache[section].map { MenuBarSnapshotItem(section: section, item: $0) }
                    )
                }
            ),
            controlItemsMissing: controlItemsMissing,
            systemMenuBarHidden: systemMenuBarHidden
        )
    }
}
