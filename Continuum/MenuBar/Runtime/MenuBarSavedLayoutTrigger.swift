//
//  MenuBarSavedLayoutTrigger.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure gate for deciding whether a cache cycle should run saved-layout apply.
///
/// The full apply path is intentionally heavyweight: it fetches fresh menu-bar
/// state, plans every section, posts synthetic drag events, then recaches. This
/// trigger keeps the expensive path behind explicit, testable signals so
/// WindowServer churn and display focus changes do not repeatedly re-sort the
/// menu bar.
enum MenuBarSavedLayoutTrigger {
    enum Trigger: Equatable, CustomStringConvertible {
        case windowIDChange
        case layoutDivergence

        var description: String {
            switch self {
            case .windowIDChange:
                "windowID change"
            case .layoutDivergence:
                "layout divergence"
            }
        }
    }

    enum SkipReason: Equatable, CustomStringConvertible {
        case emptySavedSectionOrder
        case relocationSuppressed
        case moveCooldownActive
        case noDetectedChange
        case noSavedItemsPresent

        var description: String {
            switch self {
            case .emptySavedSectionOrder:
                "savedSectionOrder is empty"
            case .relocationSuppressed:
                "suppressNextNewLeftmostItemRelocation armed"
            case .moveCooldownActive:
                "within move cooldown"
            case .noDetectedChange:
                "no windowID change and saved layout matches current"
            case .noSavedItemsPresent:
                "no saved items currently present"
            }
        }
    }

    enum Decision: Equatable {
        case apply(Trigger)
        case skip(SkipReason)

        var shouldApply: Bool {
            if case .apply = self {
                return true
            }
            return false
        }
    }

    static func evaluate(
        savedSectionOrder: [String: [String]],
        items: [MenuBarItem],
        controlItems: MenuBarControlItems,
        previousWindowIDs: [CGWindowID],
        previousDisplayID: CGDirectDisplayID?,
        currentDisplayID: CGDirectDisplayID?,
        relocationSuppressed: Bool,
        moveCooldownActive: Bool
    ) -> Decision {
        guard !savedSectionOrder.isEmpty else {
            return .skip(.emptySavedSectionOrder)
        }
        guard !relocationSuppressed else {
            return .skip(.relocationSuppressed)
        }
        guard !moveCooldownActive else {
            return .skip(.moveCooldownActive)
        }

        let currentWindowIDSet = Set(items.map(\.windowID))
        let previousWindowIDSet = Set(previousWindowIDs)
        let idsChanged = windowIDsChanged(
            previous: previousWindowIDSet,
            current: currentWindowIDSet,
            previousDisplayID: previousDisplayID,
            currentDisplayID: currentDisplayID
        )
        let trigger: Trigger?
        if idsChanged {
            trigger = .windowIDChange
        } else if currentLayoutDivergesFromSaved(
            savedSectionOrder: savedSectionOrder,
            items: items,
            controlItems: controlItems
        ) {
            trigger = .layoutDivergence
        } else {
            trigger = nil
        }

        guard let trigger else {
            return .skip(.noDetectedChange)
        }

        guard hasSavedItemCurrentlyPresent(
            savedSectionOrder: savedSectionOrder,
            items: items
        ) else {
            return .skip(.noSavedItemsPresent)
        }

        return .apply(trigger)
    }

    static func itemSectionMap(
        from savedSectionOrder: [String: [String]]
    ) -> [String: String] {
        var itemSectionMap = [String: String]()
        for (sectionKey, identifiers) in savedSectionOrder {
            for identifier in identifiers {
                itemSectionMap[identifier] = sectionKey
            }
        }
        return itemSectionMap
    }

    static func windowIDsChanged(
        previous: Set<CGWindowID>,
        current: Set<CGWindowID>,
        previousDisplayID: CGDirectDisplayID?,
        currentDisplayID: CGDirectDisplayID?
    ) -> Bool {
        guard !previous.isEmpty else { return false }
        if let previousDisplayID,
           let currentDisplayID,
           previousDisplayID != currentDisplayID
        {
            return false
        }
        return !previous.isSubset(of: current)
    }

    static func currentLayoutDivergesFromSaved(
        savedSectionOrder: [String: [String]],
        items: [MenuBarItem],
        controlItems: MenuBarControlItems
    ) -> Bool {
        let savedSectionByBaseID = savedSectionByBaseID(from: savedSectionOrder)
        guard !savedSectionByBaseID.isEmpty else { return false }

        let hiddenMinX = controlItems.hidden.bounds.minX
        let hiddenMaxX = controlItems.hidden.bounds.maxX
        let ahBounds = controlItems.alwaysHidden?.bounds

        for item in items where !item.isControlItem && item.canBeHidden && item.isMovable {
            let baseID = "\(item.tag.namespace):\(item.tag.title)"
            guard let expectedSection = savedSectionByBaseID[baseID] else {
                continue
            }

            guard let currentSection = currentSection(
                for: item,
                hiddenMinX: hiddenMinX,
                hiddenMaxX: hiddenMaxX,
                alwaysHiddenBounds: ahBounds
            ) else {
                continue
            }

            if currentSection != expectedSection {
                return true
            }
        }
        return false
    }

    private static func savedSectionByBaseID(
        from savedSectionOrder: [String: [String]]
    ) -> [String: MenuBarSection.Name] {
        var savedSectionByBaseID = [String: MenuBarSection.Name]()
        for (sectionKey, ids) in savedSectionOrder {
            guard let section = MenuBarSection.Name(rawValue: sectionKey) else {
                continue
            }
            for id in ids {
                savedSectionByBaseID[baseIdentifier(for: id)] = section
            }
        }
        return savedSectionByBaseID
    }

    private static func hasSavedItemCurrentlyPresent(
        savedSectionOrder: [String: [String]],
        items: [MenuBarItem]
    ) -> Bool {
        let currentBaseIDs = Set(items.map { "\($0.tag.namespace):\($0.tag.title)" })
        let savedBaseIDs = Set(savedSectionOrder.values.flatMap { identifiers in
            identifiers.map { baseIdentifier(for: $0) }
        })
        return !savedBaseIDs.isDisjoint(with: currentBaseIDs)
    }

    private static func currentSection(
        for item: MenuBarItem,
        hiddenMinX: CGFloat,
        hiddenMaxX: CGFloat,
        alwaysHiddenBounds: CGRect?
    ) -> MenuBarSection.Name? {
        if item.bounds.minX >= hiddenMaxX {
            return .visible
        }
        if let alwaysHiddenBounds,
           item.bounds.maxX <= alwaysHiddenBounds.minX
        {
            return .alwaysHidden
        }
        if let alwaysHiddenBounds,
           item.bounds.minX >= alwaysHiddenBounds.maxX,
           item.bounds.maxX <= hiddenMinX
        {
            return .hidden
        }
        if alwaysHiddenBounds == nil, item.bounds.maxX <= hiddenMinX {
            return .hidden
        }
        return nil
    }

    private static func baseIdentifier(for identifier: String) -> String {
        identifier
            .split(separator: ":", maxSplits: 2)
            .prefix(2)
            .joined(separator: ":")
    }
}
