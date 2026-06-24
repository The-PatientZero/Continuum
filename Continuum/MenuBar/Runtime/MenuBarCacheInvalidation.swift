//
//  MenuBarCacheInvalidation.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure decision for whether a lightweight window-list tick should recache.
///
/// The periodic tick intentionally looks only at menu-bar window IDs. Known
/// System Status Item Clone windows are filtered before comparison so screen
/// capture and menu-bar animation artifacts do not churn the cache or re-enter
/// layout restore.
enum MenuBarCacheInvalidation {
    struct Decision: Equatable {
        enum Action: Equatable {
            case keepCurrentCache
            case recache
        }

        let normalizedWindowIDs: [CGWindowID]
        let action: Action

        var shouldRecache: Bool {
            action == .recache
        }
    }

    static func evaluate(
        cachedWindowIDs: [CGWindowID],
        observedWindowIDs: [CGWindowID],
        cloneWindowIDs: Set<CGWindowID>
    ) -> Decision {
        let normalizedWindowIDs = cloneWindowIDs.isEmpty
            ? observedWindowIDs
            : observedWindowIDs.filter { !cloneWindowIDs.contains($0) }
        let action: Decision.Action = cachedWindowIDs == normalizedWindowIDs
            ? .keepCurrentCache
            : .recache

        return Decision(
            normalizedWindowIDs: normalizedWindowIDs,
            action: action
        )
    }
}
