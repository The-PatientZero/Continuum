//
//  MenuBarNewItemsPlacementPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Pure policy for the "New Items" badge and newly discovered item destination.
///
/// The manager owns persistence, layout-bar views, cache classification, and move
/// execution. This policy owns the stable placement contract that decides where
/// the badge appears and how persisted placement preferences are normalized.
enum MenuBarNewItemsPlacementPolicy {
    typealias Placement = MenuBarNewItemsPlacement

    enum ArrangedElement: Equatable {
        case item(identifier: String)
        case newItemsBadge
    }

    struct AnchorCandidate: Equatable {
        let identifier: String
        let isControlItem: Bool
        let instanceIndex: Int
    }

    enum ControlAnchor: Equatable {
        case hidden
        case alwaysHidden
    }

    enum MoveDestinationIntent: Equatable {
        case leftOfIdentifier(String)
        case rightOfIdentifier(String)
        case leftOfControl(ControlAnchor)
        case rightOfControl(ControlAnchor)
    }

    static func sectionKey(for section: MenuBarSection.Name) -> String {
        section.rawValue
    }

    static func sectionName(for key: String) -> MenuBarSection.Name? {
        MenuBarSection.Name(rawValue: key)
    }

    static func effectiveSection(
        placement: Placement,
        alwaysHiddenEnabled: Bool
    ) -> MenuBarSection.Name {
        let preferredSection = sectionName(for: placement.sectionKey) ?? .hidden
        if preferredSection == .alwaysHidden, !alwaysHiddenEnabled {
            return .hidden
        }
        return preferredSection
    }

    static func badgeIndex(
        in section: MenuBarSection.Name,
        itemIdentifiers: [String],
        placement: Placement,
        savedSectionOrder: [String: [String]],
        alwaysHiddenEnabled: Bool
    ) -> Int? {
        guard effectiveSection(placement: placement, alwaysHiddenEnabled: alwaysHiddenEnabled) == section else {
            return nil
        }

        if sectionName(for: placement.sectionKey) == section,
           let anchorIdentifier = placement.anchorIdentifier,
           let anchorIndex = resolvedAnchorIndex(
               for: anchorIdentifier,
               in: itemIdentifiers
           )
        {
            switch placement.relation {
            case .leftOfAnchor:
                return anchorIndex
            case .rightOfAnchor:
                return anchorIndex + 1
            case .sectionDefault:
                break
            }
        }

        if let nearestIndex = badgeIndexFromNearestSavedSibling(
            in: section,
            itemIdentifiers: itemIdentifiers,
            placement: placement,
            savedSectionOrder: savedSectionOrder
        ) {
            return nearestIndex
        }

        return defaultBadgeIndex(
            in: section,
            itemCount: itemIdentifiers.count,
            alwaysHiddenEnabled: alwaysHiddenEnabled
        )
    }

    static func updatedPlacement(
        for section: MenuBarSection.Name,
        arrangedElements: [ArrangedElement],
        alwaysHiddenEnabled: Bool
    ) -> Placement {
        let resolvedSection: MenuBarSection.Name = if section == .alwaysHidden, !alwaysHiddenEnabled {
            .hidden
        } else {
            section
        }

        guard let badgeIndex = arrangedElements.firstIndex(of: .newItemsBadge) else {
            return Placement(
                sectionKey: sectionKey(for: resolvedSection),
                anchorIdentifier: nil,
                relation: .sectionDefault
            )
        }

        let rightNeighbor = arrangedElements[(badgeIndex + 1) ..< arrangedElements.count]
            .compactMap(\.itemIdentifier)
            .first
        let leftNeighbor = arrangedElements[..<badgeIndex]
            .reversed()
            .compactMap(\.itemIdentifier)
            .first

        if let rightNeighbor {
            return Placement(
                sectionKey: sectionKey(for: resolvedSection),
                anchorIdentifier: rightNeighbor,
                relation: .leftOfAnchor
            )
        }
        if let leftNeighbor {
            return Placement(
                sectionKey: sectionKey(for: resolvedSection),
                anchorIdentifier: leftNeighbor,
                relation: .rightOfAnchor
            )
        }
        return Placement(
            sectionKey: sectionKey(for: resolvedSection),
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
    }

    static func appliedPlacement(
        _ placement: Placement,
        hiddenItems: [AnchorCandidate],
        alwaysHiddenEnabled: Bool
    ) -> Placement {
        let preferredSection = sectionName(for: placement.sectionKey) ?? .hidden
        let clampedToHidden = preferredSection == .alwaysHidden && !alwaysHiddenEnabled
        let resolvedSection: MenuBarSection.Name = clampedToHidden ? .hidden : preferredSection

        guard clampedToHidden else {
            return Placement(
                sectionKey: sectionKey(for: resolvedSection),
                anchorIdentifier: placement.anchorIdentifier,
                relation: placement.relation
            )
        }

        if let rightmostHiddenItem = hiddenItems.first(where: { !$0.isControlItem && $0.instanceIndex == 0 }) {
            return Placement(
                sectionKey: sectionKey(for: resolvedSection),
                anchorIdentifier: rightmostHiddenItem.identifier,
                relation: .leftOfAnchor
            )
        }

        return Placement(
            sectionKey: sectionKey(for: resolvedSection),
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
    }

    static func resolvedAnchorIdentifier(
        for anchorIdentifier: String,
        in itemIdentifiers: [String]
    ) -> String? {
        if itemIdentifiers.contains(anchorIdentifier) {
            return anchorIdentifier
        }

        let stableIdentifier = stableAnchorIdentifier(from: anchorIdentifier)
        return itemIdentifiers.first { identifier in
            stableAnchorIdentifier(from: identifier) == stableIdentifier
        }
    }

    static func moveDestinationIntent(
        placement: Placement,
        liveSectionItemIdentifiers: [String],
        targetSection: MenuBarSection.Name,
        alwaysHiddenEnabled: Bool,
        hasAlwaysHiddenControl: Bool
    ) -> MoveDestinationIntent {
        if sectionName(for: placement.sectionKey) == targetSection,
           let anchorIdentifier = placement.anchorIdentifier,
           let resolvedAnchorIdentifier = resolvedAnchorIdentifier(
               for: anchorIdentifier,
               in: liveSectionItemIdentifiers
           )
        {
            switch placement.relation {
            case .leftOfAnchor:
                return .leftOfIdentifier(resolvedAnchorIdentifier)
            case .rightOfAnchor:
                return .rightOfIdentifier(resolvedAnchorIdentifier)
            case .sectionDefault:
                break
            }
        }

        switch targetSection {
        case .visible:
            return .rightOfControl(.hidden)
        case .hidden:
            if alwaysHiddenEnabled, hasAlwaysHiddenControl {
                return .rightOfControl(.alwaysHidden)
            }
            return .leftOfControl(.hidden)
        case .alwaysHidden:
            if hasAlwaysHiddenControl {
                return .leftOfControl(.alwaysHidden)
            }
            return .leftOfControl(.hidden)
        }
    }

    private static func resolvedAnchorIndex(
        for anchorIdentifier: String,
        in itemIdentifiers: [String]
    ) -> Int? {
        guard let resolvedIdentifier = resolvedAnchorIdentifier(for: anchorIdentifier, in: itemIdentifiers) else {
            return nil
        }
        return itemIdentifiers.firstIndex(of: resolvedIdentifier)
    }

    private static func badgeIndexFromNearestSavedSibling(
        in section: MenuBarSection.Name,
        itemIdentifiers: [String],
        placement: Placement,
        savedSectionOrder: [String: [String]]
    ) -> Int? {
        guard let anchorIdentifier = placement.anchorIdentifier,
              placement.relation != .sectionDefault,
              sectionName(for: placement.sectionKey) == section,
              let savedOrder = savedSectionOrder[sectionKey(for: section)],
              let anchorPosition = savedOrder.firstIndex(of: anchorIdentifier)
        else {
            return nil
        }

        if placement.relation == .leftOfAnchor {
            for index in stride(from: anchorPosition - 1, through: 0, by: -1) {
                if let currentIndex = itemIdentifiers.firstIndex(of: savedOrder[index]) {
                    return currentIndex + 1
                }
            }
            for index in (anchorPosition + 1) ..< savedOrder.count {
                if let currentIndex = itemIdentifiers.firstIndex(of: savedOrder[index]) {
                    return currentIndex
                }
            }
        } else {
            for index in (anchorPosition + 1) ..< savedOrder.count {
                if let currentIndex = itemIdentifiers.firstIndex(of: savedOrder[index]) {
                    return currentIndex
                }
            }
            for index in stride(from: anchorPosition - 1, through: 0, by: -1) {
                if let currentIndex = itemIdentifiers.firstIndex(of: savedOrder[index]) {
                    return currentIndex + 1
                }
            }
        }

        return nil
    }

    private static func stableAnchorIdentifier(from identifier: String) -> String {
        identifier
    }

    private static func defaultBadgeIndex(
        in section: MenuBarSection.Name,
        itemCount: Int,
        alwaysHiddenEnabled: Bool
    ) -> Int {
        switch section {
        case .visible:
            return 0
        case .hidden:
            return alwaysHiddenEnabled ? 0 : itemCount
        case .alwaysHidden:
            return itemCount
        }
    }
}

private extension MenuBarNewItemsPlacementPolicy.ArrangedElement {
    var itemIdentifier: String? {
        if case let .item(identifier) = self {
            return identifier
        }
        return nil
    }
}
