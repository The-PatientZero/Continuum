//
//  MenuBarSavedOrderPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Pure policy for turning a live menu bar cache into persisted savedSectionOrder.
///
/// The manager owns UserDefaults and live cache mutation. This policy owns the
/// stability contract: only high-confidence layout items and the visible control
/// item can enter saved order, transient/pending-rehide observations are masked,
/// and closed-app entries keep their prior slots.
enum MenuBarSavedOrderPolicy {
    static func build(
        from cache: MenuBarItemCache,
        previousSavedSectionOrder: [String: [String]],
        pendingReturnDestinations: [String: [String: String]],
        pendingRelocations: [String: String]
    ) -> [String: [String]] {
        var newOrder = [String: [String]]()
        let pendingRehideTagIDs = LayoutSolver.pendingRehideTagIdentifiers(
            pendingReturnDestinations: pendingReturnDestinations,
            pendingRelocations: pendingRelocations,
            waitForRelaunchPrefix: PendingLedger.waitForRelaunchPrefix
        )

        let currentIdentifierIndex = currentIdentifierIndex(
            from: cache,
            pendingRehideTagIDs: pendingRehideTagIDs
        )

        for section in MenuBarSection.Name.allCases {
            let currentInSection = cache[section]
                .filter { isCurrentSavedOrderItem($0, pendingRehideTagIDs: pendingRehideTagIDs) }
                .map(\.uniqueIdentifier)

            let oldSavedForSection = (previousSavedSectionOrder[sectionKey(for: section)] ?? [])
                .filter { !isPrunableSavedIdentifier($0) }

            let identifiers = LayoutSolver.planSectionOrder(
                currentInSection: currentInSection,
                oldSavedForSection: oldSavedForSection,
                allCurrentIdentifiers: currentIdentifierIndex.identifiers,
                allCurrentBaseIdentifiers: currentIdentifierIndex.baseIdentifiers
            )

            if !identifiers.isEmpty {
                newOrder[sectionKey(for: section)] = identifiers
            }
        }

        return newOrder
    }

    static func sectionKey(for section: MenuBarSection.Name) -> String {
        section.rawValue
    }

    static func baseIdentifier(_ identifier: String) -> String {
        let parts = identifier.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        return parts.prefix(2).joined(separator: ":")
    }

    static func prunedSavedSectionOrder(_ order: [String: [String]]) -> [String: [String]] {
        var pruned = [String: [String]]()
        for (sectionKey, identifiers) in order {
            let filtered = identifiers.filter { !isPrunableSavedIdentifier($0) }
            if !filtered.isEmpty {
                pruned[sectionKey] = filtered
            }
        }
        return pruned
    }

    static func sanitizedLayoutEditorOrder(
        _ order: [MenuBarSection.Name: [String]]
    ) -> [String: [String]] {
        var persistedOrder = [String: [String]]()
        for section in MenuBarSection.Name.allCases {
            let identifiers = (order[section] ?? [])
                .filter { !$0.isEmpty && !isPrunableSavedIdentifier($0) }
            if !identifiers.isEmpty {
                persistedOrder[sectionKey(for: section)] = identifiers
            }
        }
        return persistedOrder
    }

    static func isPrunableSavedIdentifier(_ identifier: String) -> Bool {
        isControlItemIdentifier(identifier) ||
            isContinuumStructuralIdentifier(identifier) ||
            isGenericControlCenterSavedIdentifier(identifier)
    }

    static func isGenericControlCenterSavedIdentifier(_ identifier: String) -> Bool {
        let parts = identifier.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[0] == "com.apple.controlcenter" else {
            return false
        }

        let title = String(parts[1])
        return title.isEmpty || MarkerPairResolver.isGenericControlCenterTitle(title)
    }

    private struct CurrentIdentifierIndex: Equatable {
        let identifiers: Set<String>
        let baseIdentifiers: Set<String>
    }

    private static func currentIdentifierIndex(
        from cache: MenuBarItemCache,
        pendingRehideTagIDs: Set<String>
    ) -> CurrentIdentifierIndex {
        var allCurrentIdentifiers = Set<String>()
        var allCurrentBaseIdentifiers = Set<String>()

        for section in MenuBarSection.Name.allCases {
            for item in cache[section] where isSavedOrderCandidate(item) {
                guard !pendingRehideTagIDs.contains(item.tag.tagIdentifier) else { continue }
                allCurrentBaseIdentifiers.insert(baseIdentifier(for: item))
                guard !item.isTransientControlCenterItem else { continue }
                allCurrentIdentifiers.insert(item.uniqueIdentifier)
            }
        }

        return CurrentIdentifierIndex(
            identifiers: allCurrentIdentifiers,
            baseIdentifiers: allCurrentBaseIdentifiers
        )
    }

    private static func isCurrentSavedOrderItem(
        _ item: MenuBarItem,
        pendingRehideTagIDs: Set<String>
    ) -> Bool {
        isSavedOrderCandidate(item) &&
            !item.isTransientControlCenterItem &&
            !pendingRehideTagIDs.contains(item.tag.tagIdentifier)
    }

    private static func isSavedOrderCandidate(_ item: MenuBarItem) -> Bool {
        if item.tag == .visibleControlItem {
            return true
        }
        return !item.isControlItem &&
            item.identityConfidence.allowsPersistence &&
            !item.isContinuumStructuralItem
    }

    private static func baseIdentifier(for item: MenuBarItem) -> String {
        "\(item.tag.namespace):\(item.tag.title)"
    }

    private static func isControlItemIdentifier(_ identifier: String) -> Bool {
        identifier.contains(ControlItem.Identifier.visible.rawValue) ||
            identifier.contains(ControlItem.Identifier.hidden.rawValue) ||
            identifier.contains(ControlItem.Identifier.alwaysHidden.rawValue)
    }

    private static func isContinuumStructuralIdentifier(_ identifier: String) -> Bool {
        let prefix = "\(Constants.bundleIdentifier):"
        guard identifier.hasPrefix(prefix) else {
            return false
        }

        let title = identifier.dropFirst(prefix.count)
        return title.isEmpty ||
            title.hasPrefix(":") ||
            title.hasPrefix("Continuum.ControlItem.")
    }
}
