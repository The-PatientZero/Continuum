//
//  MenuBarMoveRecoveryPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Pure policy for post-move recovery of blocked menu bar items.
///
/// macOS can strand an item at x=-1 while moving it into the always-hidden
/// section. Recover only that specific failure mode; moving an item back to the
/// visible section after any other target would undo a valid user layout.
enum MenuBarMoveRecoveryPolicy {
    enum Decision: Equatable {
        case none
        case restoreToVisible
    }

    static func decision(
        after command: MenuBarMoveCommand,
        itemIsBlocked: Bool
    ) -> Decision {
        guard itemIsBlocked else {
            return .none
        }

        guard command.destination.targetItem.tag == .alwaysHiddenControlItem else {
            return .none
        }

        return .restoreToVisible
    }

    static func visibleRecoveryDestination(
        hiddenControlItem: MenuBarItem
    ) -> MenuBarMoveDestination {
        .rightOfItem(hiddenControlItem)
    }
}
