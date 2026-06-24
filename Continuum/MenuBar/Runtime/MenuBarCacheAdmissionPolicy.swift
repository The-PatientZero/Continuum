//
//  MenuBarCacheAdmissionPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Pure gate for deciding whether a full cache cycle should run.
///
/// The cache cycle reads the WindowServer, reconciles identity, may move control
/// items, and can dispatch a saved-layout apply. Keep it out of moments where
/// the observed menu bar is predictably transient.
enum MenuBarCacheAdmissionPolicy {
    static let recentMoveQuietWindow: Duration = .seconds(1)

    enum PreGateDecision: Equatable {
        case attemptGate
        case skip(SkipReason)
    }

    enum GateDecision: Equatable {
        case run
        case skip(SkipReason)
    }

    enum SkipReason: Equatable, CustomStringConvertible {
        case recentMove
        case userDragging
        case cacheInProgress

        var description: String {
            switch self {
            case .recentMove:
                "recent item movement"
            case .userDragging:
                "user is cmd-dragging"
            case .cacheInProgress:
                "serial cache operation already in progress"
            }
        }
    }

    static func preGateDecision(
        skipRecentMoveCheck: Bool,
        recentMoveOccurred: Bool,
        userIsDraggingMenuBarItem: Bool
    ) -> PreGateDecision {
        if !skipRecentMoveCheck, recentMoveOccurred {
            return .skip(.recentMove)
        }
        if userIsDraggingMenuBarItem {
            return .skip(.userDragging)
        }
        return .attemptGate
    }

    static func gateDecision(cacheGateAcquired: Bool) -> GateDecision {
        cacheGateAcquired ? .run : .skip(.cacheInProgress)
    }
}
