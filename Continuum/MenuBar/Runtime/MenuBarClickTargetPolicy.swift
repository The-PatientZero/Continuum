//
//  MenuBarClickTargetPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure policy for choosing click targets and activation routes.
///
/// The manager owns WindowServer reads, Accessibility presses, and CGEvent
/// posting. This policy keeps the deterministic matching and route decisions
/// shared by direct activation and temporary reveal fallback clicks.
enum MenuBarClickTargetPolicy {
    enum ActivationRoute: Equatable {
        case clickInPlace
        case temporarilyReveal
    }

    static func activationRoute(itemIsOnScreen: Bool) -> ActivationRoute {
        itemIsOnScreen ? .clickInPlace : .temporarilyReveal
    }

    static func shouldAttemptAccessibilityPress(
        mouseButton: CGMouseButton,
        isElectronItem: Bool
    ) -> Bool {
        mouseButton == .left && isElectronItem
    }

    static func refreshedTarget(
        matching item: MenuBarItem,
        in candidates: [MenuBarItem]
    ) -> MenuBarItem? {
        candidates.first(where: { $0.windowID == item.windowID }) ??
            candidates.first(where: {
                $0.tag.matchesIgnoringWindowID(item.tag) &&
                    ($0.sourcePID ?? $0.ownerPID) == (item.sourcePID ?? item.ownerPID)
            })
    }

    static func clickPoint(for bounds: CGRect) -> CGPoint {
        bounds.center
    }
}
