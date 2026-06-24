//
//  MenuBarMoveVerification.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Pure cache-level verification for completed menu bar move commands.
///
/// Synthetic menu-bar moves can report an event failure even after the Window
/// Server settles the item in the requested slot. This verifier gives every
/// caller the same rule for accepting or rejecting that observed placement.
enum MenuBarMoveVerification {
    enum Outcome: Equatable, CustomStringConvertible {
        case reachedDestination
        case itemMissingFromExpectedSection
        case targetMissingFromExpectedSection
        case wrongRelativePosition(
            itemIndex: Int,
            targetIndex: Int,
            relation: MenuBarMovePreflight.Relation
        )

        var didReachDestination: Bool {
            self == .reachedDestination
        }

        var description: String {
            switch self {
            case .reachedDestination:
                "reachedDestination"
            case .itemMissingFromExpectedSection:
                "itemMissingFromExpectedSection"
            case .targetMissingFromExpectedSection:
                "targetMissingFromExpectedSection"
            case let .wrongRelativePosition(itemIndex, targetIndex, relation):
                "wrongRelativePosition(itemIndex=\(itemIndex), targetIndex=\(targetIndex), relation=\(relation))"
            }
        }
    }

    static func evaluate(
        item: MenuBarItem,
        destination: MenuBarMoveDestination,
        expectedSection: MenuBarSection.Name,
        cache: MenuBarItemCache
    ) -> Outcome {
        let sectionItems = cache[expectedSection]
        guard let itemIndex = sectionItems.firstIndex(where: { $0.tag == item.tag }) else {
            return .itemMissingFromExpectedSection
        }

        let target = destination.targetItem
        if target.isControlItem {
            return .reachedDestination
        }

        guard let targetIndex = sectionItems.firstIndex(where: { $0.tag == target.tag }) else {
            return .targetMissingFromExpectedSection
        }

        let relation: MenuBarMovePreflight.Relation
        let reached: Bool
        switch destination {
        case .leftOfItem:
            relation = .leftOfItem
            reached = itemIndex + 1 == targetIndex
        case .rightOfItem:
            relation = .rightOfItem
            reached = itemIndex == targetIndex + 1
        }

        if reached {
            return .reachedDestination
        }

        return .wrongRelativePosition(
            itemIndex: itemIndex,
            targetIndex: targetIndex,
            relation: relation
        )
    }

    static func didReachDestination(
        item: MenuBarItem,
        destination: MenuBarMoveDestination,
        expectedSection: MenuBarSection.Name,
        cache: MenuBarItemCache
    ) -> Bool {
        evaluate(
            item: item,
            destination: destination,
            expectedSection: expectedSection,
            cache: cache
        ).didReachDestination
    }
}
