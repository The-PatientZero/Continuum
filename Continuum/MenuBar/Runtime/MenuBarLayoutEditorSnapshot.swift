//
//  MenuBarLayoutEditorSnapshot.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A stable item shape for the Settings layout editor.
struct MenuBarLayoutEditorItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemIcon: MenuBarSystemMenuExtraIcon?
    let iconBundleIdentifier: String?
    let iconProcessIdentifier: pid_t?
    let isAvailable: Bool
    let isMovable: Bool
    let isIdentityResolved: Bool

    var systemSymbolName: String? {
        systemIcon?.systemSymbolName
    }
}

/// A staged, display-ready view of the user's saved/current layout.
struct MenuBarLayoutEditorSnapshot: Equatable {
    let sections: [MenuBarSection.Name: [MenuBarLayoutEditorItem]]
}

/// Builds Settings layout-editor snapshots from runtime cache and saved order.
///
/// The manager owns live cache refresh, persistence, and move execution. This
/// policy owns the read-side contract: which items appear in the editor, how
/// live items merge with closed-app saved slots, and how identity confidence is
/// represented for UI staging.
enum MenuBarLayoutEditorPolicy {
    static func snapshot(
        cache: MenuBarItemCache,
        savedSectionOrder: [String: [String]],
        fallbackSectionOrder: [String: [String]]
    ) -> MenuBarLayoutEditorSnapshot {
        var currentItemsByIdentifier = [String: MenuBarItem]()
        var currentSectionByIdentifier = [String: MenuBarSection.Name]()

        for section in MenuBarSection.Name.allCases {
            for item in cache[section] where isSnapshotItem(item) {
                currentItemsByIdentifier[item.uniqueIdentifier] = item
                currentSectionByIdentifier[item.uniqueIdentifier] = section
            }
        }

        let currentBaseIdentifiers = Set(
            currentItemsByIdentifier.keys.map(MenuBarSavedOrderPolicy.baseIdentifier)
        )
        let sourceOrder = savedSectionOrder.isEmpty ? fallbackSectionOrder : savedSectionOrder

        var seenIdentifiers = Set<String>()
        var sections = Dictionary(
            uniqueKeysWithValues: MenuBarSection.Name.allCases.map { ($0, [MenuBarLayoutEditorItem]()) }
        )

        for section in MenuBarSection.Name.allCases {
            let identifiers = sourceOrder[MenuBarSavedOrderPolicy.sectionKey(for: section)] ?? []
            for identifier in identifiers {
                let hasCurrentItem = currentItemsByIdentifier[identifier] != nil
                let hasLiveAlias = !hasCurrentItem && currentBaseIdentifiers.contains(
                    MenuBarSavedOrderPolicy.baseIdentifier(identifier)
                )
                guard !seenIdentifiers.contains(identifier),
                      !hasLiveAlias,
                      !MenuBarSavedOrderPolicy.isPrunableSavedIdentifier(identifier)
                else {
                    continue
                }

                sections[section, default: []].append(
                    editorItem(
                        for: identifier,
                        currentItem: currentItemsByIdentifier[identifier]
                    )
                )
                seenIdentifiers.insert(identifier)
            }
        }

        for section in MenuBarSection.Name.allCases {
            for item in cache[section] where isSnapshotItem(item) && !seenIdentifiers.contains(item.uniqueIdentifier) {
                sections[currentSectionByIdentifier[item.uniqueIdentifier] ?? section, default: []].append(
                    editorItem(for: item.uniqueIdentifier, currentItem: item)
                )
                seenIdentifiers.insert(item.uniqueIdentifier)
            }
        }

        return MenuBarLayoutEditorSnapshot(sections: sections)
    }

    static func isSnapshotItem(_ item: MenuBarItem) -> Bool {
        !item.isControlItem &&
            !item.isSystemClone &&
            !item.isTransientControlCenterItem &&
            !item.isUnresolvedControlCenterPlaceholder &&
            !item.isContinuumStructuralItem
    }

    static func isMovableItem(_ item: MenuBarItem) -> Bool {
        // Title-less Control Center modules (Wi-Fi, Bluetooth, Sound, etc.) still
        // appear in the editor so it mirrors the real menu bar, but they are
        // shown locked: macOS reports them with empty titles, so Continuum
        // cannot yet identify or reliably move them, and dragging one only
        // times out the move watchdog. They unlock once title resolution can name them.
        item.isMovable && item.canBeHidden && !item.isTitlelessControlCenterModule
    }

    private static func editorItem(
        for identifier: String,
        currentItem: MenuBarItem?
    ) -> MenuBarLayoutEditorItem {
        if let currentItem {
            return MenuBarLayoutEditorItem(
                id: identifier,
                title: title(for: currentItem),
                subtitle: subtitle(for: currentItem),
                systemIcon: MenuBarSystemMenuExtraMetadata.icon(for: currentItem),
                iconBundleIdentifier: iconBundleIdentifier(
                    for: identifier,
                    currentItem: currentItem
                ),
                iconProcessIdentifier: currentItem.sourcePID,
                isAvailable: true,
                isMovable: isMovableItem(currentItem),
                isIdentityResolved: currentItem.sourcePID != nil ||
                    MenuBarSystemMenuExtraMetadata.displayName(for: currentItem) != nil
            )
        }

        return MenuBarLayoutEditorItem(
            id: identifier,
            title: displayName(forSavedIdentifier: identifier),
            subtitle: "Saved item",
            systemIcon: MenuBarSystemMenuExtraMetadata.icon(forSavedIdentifier: identifier),
            iconBundleIdentifier: bundleIdentifier(forSavedIdentifier: identifier),
            iconProcessIdentifier: nil,
            isAvailable: false,
            isMovable: true,
            isIdentityResolved: true
        )
    }

    private static func iconBundleIdentifier(
        for identifier: String,
        currentItem: MenuBarItem
    ) -> String? {
        currentItem.sourceApplication?.bundleIdentifier ??
            bundleIdentifier(forSavedIdentifier: identifier)
    }

    private static func title(for item: MenuBarItem) -> String {
        if let systemName = MenuBarSystemMenuExtraMetadata.displayName(for: item) {
            return systemName
        }
        if item.sourcePID == nil && item.displayName == "Menu Bar Item" {
            return "Menu Extra"
        }
        return item.displayName
    }

    private static func subtitle(for item: MenuBarItem) -> String {
        if MenuBarSystemMenuExtraMetadata.displayName(for: item) != nil {
            return "System menu extra"
        }
        if let bundleIdentifier = item.sourceApplication?.bundleIdentifier {
            return bundleIdentifier
        }
        if item.sourcePID == nil {
            return "Identity pending"
        }
        return "\(item.tag.namespace)"
    }

    private static func displayName(forSavedIdentifier identifier: String) -> String {
        let parts = identifier.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count >= 2,
           let systemName = MenuBarSystemMenuExtraMetadata.displayName(
               namespace: String(parts[0]),
               title: String(parts[1])
           )
        {
            return systemName
        }
        guard let rawTitle = parts.dropFirst().first else {
            return identifier
        }

        let title = rawTitle
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        return title.isEmpty ? identifier : title
    }

    private static func bundleIdentifier(forSavedIdentifier identifier: String) -> String? {
        guard let namespace = identifier.split(separator: ":", omittingEmptySubsequences: false).first else {
            return nil
        }
        let bundleIdentifier = String(namespace)
        return bundleIdentifier.contains(".") ? bundleIdentifier : nil
    }
}
