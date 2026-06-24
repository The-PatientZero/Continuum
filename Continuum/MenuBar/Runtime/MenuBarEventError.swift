//
//  MenuBarEventError.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Error boundary for synthetic menu bar event operations.
///
/// Move and click execution can fail for different runtime reasons: missing
/// geometry, invalid event sources, immovable items, or operation timeouts.
/// Keeping those failures as a standalone runtime type lets move execution,
/// click execution, diagnostics, and recovery code share one contract instead
/// of treating them as manager-private details.
enum MenuBarEventError: CustomStringConvertible, LocalizedError {
    /// A generic indication of a failure.
    case cannotComplete
    /// An event source cannot be created or is otherwise invalid.
    case invalidEventSource
    /// The location of the mouse cannot be found.
    case missingMouseLocation
    /// A failure during the creation of an event.
    case eventCreationFailure(MenuBarItem)
    /// A timeout during an event operation.
    case eventOperationTimeout(MenuBarItem)
    /// A menu bar item is not movable.
    case itemNotMovable(MenuBarItem)
    /// A timeout waiting for a menu bar item to respond to an event.
    case itemResponseTimeout(MenuBarItem)
    /// A menu bar item's bounds cannot be found.
    case missingItemBounds(MenuBarItem)

    var description: String {
        switch self {
        case .cannotComplete:
            "\(Self.self).cannotComplete"
        case .invalidEventSource:
            "\(Self.self).invalidEventSource"
        case .missingMouseLocation:
            "\(Self.self).missingMouseLocation"
        case let .eventCreationFailure(item):
            "\(Self.self).eventCreationFailure(item: \(item.tag))"
        case let .eventOperationTimeout(item):
            "\(Self.self).eventOperationTimeout(item: \(item.tag))"
        case let .itemNotMovable(item):
            "\(Self.self).itemNotMovable(item: \(item.tag))"
        case let .itemResponseTimeout(item):
            "\(Self.self).itemResponseTimeout(item: \(item.tag))"
        case let .missingItemBounds(item):
            "\(Self.self).missingItemBounds(item: \(item.tag))"
        }
    }

    var errorDescription: String? {
        switch self {
        case .cannotComplete:
            "Operation could not be completed"
        case .invalidEventSource:
            "Invalid event source"
        case .missingMouseLocation:
            "Missing mouse location"
        case let .eventCreationFailure(item):
            "Could not create event for \"\(item.displayName)\""
        case let .eventOperationTimeout(item):
            "Event operation timed out for \"\(item.displayName)\""
        case let .itemNotMovable(item):
            "\"\(item.displayName)\" is not movable"
        case let .itemResponseTimeout(item):
            "\"\(item.displayName)\" took too long to respond"
        case let .missingItemBounds(item):
            "Missing bounds rectangle for \"\(item.displayName)\""
        }
    }

    var recoverySuggestion: String? {
        if case .itemNotMovable = self { return nil }
        return "Please try again. If the error persists, please file a bug report."
    }
}
