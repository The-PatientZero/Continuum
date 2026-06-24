//
//  MenuBarMoveDestination.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Destination for a menu bar item move operation.
///
/// Move destinations are part of the runtime command model, not manager
/// ownership. Keeping them standalone lets cache mutation, move planning,
/// temporary reveal, saved-layout restore, and UI drag/drop share one explicit
/// contract.
enum MenuBarMoveDestination: Equatable {
    /// The destination to the left of the given target item.
    case leftOfItem(MenuBarItem)

    /// The destination to the right of the given target item.
    case rightOfItem(MenuBarItem)

    /// The destination's target item.
    var targetItem: MenuBarItem {
        switch self {
        case let .leftOfItem(item), let .rightOfItem(item): item
        }
    }

    var isLeftOfTarget: Bool {
        switch self {
        case .leftOfItem: true
        case .rightOfItem: false
        }
    }

    var isRightOfTarget: Bool {
        !isLeftOfTarget
    }

    /// A string to use for logging purposes.
    var logString: String {
        switch self {
        case let .leftOfItem(item): "left of \(item.logString)"
        case let .rightOfItem(item): "right of \(item.logString)"
        }
    }
}
