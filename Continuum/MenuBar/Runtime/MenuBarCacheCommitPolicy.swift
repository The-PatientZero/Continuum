//
//  MenuBarCacheCommitPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Pure policy for committing a cache cycle and deciding whether the observed
/// order is safe to persist as the user's saved menu bar layout.
enum MenuBarCacheCommitPolicy {
    static let staleRestoringItemOrderTimeout: TimeInterval = 10

    enum CacheUpdateAction: Equatable {
        case recordSnapshotOnly
        case commitCache
    }

    enum RestorationFlagAction: Equatable {
        case keep
        case clearStale
    }

    enum SavedOrderPersistenceDecision: Equatable {
        case persist
        case skip(SkipReason)
    }

    enum SkipReason: Equatable, CustomStringConvertible {
        case cacheUnchanged
        case restoringItemOrder
        case resettingLayout
        case startupSettling
        case temporarilyShownItemsInFlight
        case blockedItems

        var description: String {
            switch self {
            case .cacheUnchanged:
                "cache unchanged"
            case .restoringItemOrder:
                "saved layout restore in flight"
            case .resettingLayout:
                "layout reset in flight"
            case .startupSettling:
                "startup settling in flight"
            case .temporarilyShownItemsInFlight:
                "temporary reveal in flight"
            case .blockedItems:
                "blocked items detected"
            }
        }
    }

    static func cacheUpdateAction(cacheDidChange: Bool) -> CacheUpdateAction {
        cacheDidChange ? .commitCache : .recordSnapshotOnly
    }

    static func restorationFlagAction(
        isRestoringItemOrder: Bool,
        startedAt: Date?,
        now: Date = Date()
    ) -> RestorationFlagAction {
        guard isRestoringItemOrder, let startedAt else {
            return .keep
        }

        return now.timeIntervalSince(startedAt) > staleRestoringItemOrderTimeout
            ? .clearStale
            : .keep
    }

    static func savedOrderPersistenceDecision(
        cacheDidChange: Bool,
        isRestoringItemOrder: Bool,
        isResettingLayout: Bool,
        isInStartupSettling: Bool,
        temporarilyShownItemContextsIsEmpty: Bool,
        hasBlockedItems: Bool
    ) -> SavedOrderPersistenceDecision {
        guard cacheDidChange else {
            return .skip(.cacheUnchanged)
        }
        guard !isRestoringItemOrder else {
            return .skip(.restoringItemOrder)
        }
        guard !isResettingLayout else {
            return .skip(.resettingLayout)
        }
        guard !isInStartupSettling else {
            return .skip(.startupSettling)
        }
        guard temporarilyShownItemContextsIsEmpty else {
            return .skip(.temporarilyShownItemsInFlight)
        }
        guard !hasBlockedItems else {
            return .skip(.blockedItems)
        }

        return .persist
    }

    static func isBlockedWindowBounds(_ bounds: CGRect) -> Bool {
        bounds.origin.x == -1
    }

    static func containsBlockedItems(
        in cache: MenuBarItemCache,
        currentBoundsForItem: (MenuBarItem) -> CGRect?
    ) -> Bool {
        MenuBarSection.Name.allCases.contains { section in
            cache[section].contains { item in
                let bounds = currentBoundsForItem(item) ?? item.bounds
                return isBlockedWindowBounds(bounds)
            }
        }
    }
}
