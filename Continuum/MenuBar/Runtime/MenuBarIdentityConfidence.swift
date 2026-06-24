//
//  MenuBarIdentityConfidence.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Confidence level for acting on a menu bar item's recovered identity.
///
/// The menu bar runtime can observe windows more readily than it can prove
/// ownership. Keeping confidence explicit lets planning and diagnostics reject
/// low-trust items before they are persisted or moved.
enum MenuBarIdentityConfidence: Int, CaseIterable, Comparable, CustomStringConvertible {
    /// A Continuum-owned structural control item.
    case structural = 5

    /// A status item with a resolved source process.
    case stable = 4

    /// A non-Control-Center item whose source process is not resolved.
    case titleOnly = 3

    /// A Control Center placeholder whose owning app is not resolved yet.
    case unresolved = 2

    /// A short-lived system or Control Center item that should be observed only.
    case transient = 1

    /// A WindowServer clone or otherwise invalid management candidate.
    case invalid = 0

    static func < (lhs: MenuBarIdentityConfidence, rhs: MenuBarIdentityConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Whether this item is safe to include in persisted user layout state.
    var allowsPersistence: Bool {
        switch self {
        case .stable:
            true
        case .structural, .titleOnly, .unresolved, .transient, .invalid:
            false
        }
    }

    /// Whether this item is safe to target with automated move events.
    var allowsAutomatedMove: Bool {
        switch self {
        case .structural, .stable:
            true
        case .titleOnly, .unresolved, .transient, .invalid:
            false
        }
    }

    var description: String {
        switch self {
        case .structural:
            "structural"
        case .stable:
            "stable"
        case .titleOnly:
            "titleOnly"
        case .unresolved:
            "unresolved"
        case .transient:
            "transient"
        case .invalid:
            "invalid"
        }
    }
}

extension MenuBarItem {
    /// Runtime confidence for decisions that would mutate or persist this item.
    var identityConfidence: MenuBarIdentityConfidence {
        if isSystemClone {
            return .invalid
        }
        if isControlItem || isContinuumStructuralItem {
            return .structural
        }
        if isTransientControlCenterItem || isTitlelessControlCenterModule {
            return .transient
        }
        if isUnresolvedControlCenterPlaceholder {
            return .unresolved
        }
        if sourcePID != nil {
            return .stable
        }
        if tag.namespace == .controlCenter {
            return .unresolved
        }
        return .titleOnly
    }
}
