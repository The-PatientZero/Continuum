//
//  MenuBarMovePreflight.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Pure preflight for menu bar move execution.
struct MenuBarMovePreflight: Equatable {
    enum Relation: Equatable {
        case leftOfItem
        case rightOfItem
    }

    enum Decision: Equatable {
        case allow
        case noOp(RejectionReason)
        case reject(RejectionReason)
    }

    enum RejectionReason: Equatable, CustomStringConvertible {
        case invalidIdentity(MenuBarIdentityConfidence)
        case itemNotMovable
        case blockedItemRequiresVisibleRecovery
        case systemClone

        var description: String {
            switch self {
            case let .invalidIdentity(confidence):
                "invalidIdentity(\(confidence))"
            case .itemNotMovable:
                "itemNotMovable"
            case .blockedItemRequiresVisibleRecovery:
                "blockedItemRequiresVisibleRecovery"
            case .systemClone:
                "systemClone"
            }
        }
    }

    static func evaluate(
        item: MenuBarItem,
        relation: Relation,
        isBlocked: Bool
    ) -> Decision {
        if item.isSystemClone {
            return .noOp(.systemClone)
        }

        guard item.identityConfidence.allowsAutomatedMove else {
            return .reject(.invalidIdentity(item.identityConfidence))
        }

        guard item.isMovable else {
            return .reject(.itemNotMovable)
        }

        if isBlocked, relation != .rightOfItem {
            return .reject(.blockedItemRequiresVisibleRecovery)
        }

        return .allow
    }
}
