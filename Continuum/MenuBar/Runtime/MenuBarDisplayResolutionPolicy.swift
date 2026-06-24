//
//  MenuBarDisplayResolutionPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure policy for choosing the display that should host a runtime operation.
///
/// The manager owns NSScreen, HID, and WindowServer reads. This policy owns the
/// fallback order so multi-display churn does not create subtly different
/// behavior between moves and temporary reveals.
enum MenuBarDisplayResolutionPolicy {
    struct ScreenObservation: Equatable {
        let displayID: CGDirectDisplayID
        let frame: CGRect
    }

    static func moveDisplayID(
        explicitDisplayID: CGDirectDisplayID?,
        bestScreenDisplayID: CGDirectDisplayID?,
        activeMenuBarDisplayID: CGDirectDisplayID?,
        mainDisplayID: CGDirectDisplayID
    ) -> CGDirectDisplayID {
        explicitDisplayID ??
            bestScreenDisplayID ??
            activeMenuBarDisplayID ??
            mainDisplayID
    }

    static func temporaryRevealDisplayID(
        explicitDisplayID: CGDirectDisplayID?,
        itemBounds: CGRect,
        screens: [ScreenObservation],
        activeMenuBarDisplayID: CGDirectDisplayID?,
        mainDisplayID: CGDirectDisplayID
    ) -> CGDirectDisplayID {
        explicitDisplayID ??
            screens.first { $0.frame.intersects(itemBounds) }?.displayID ??
            activeMenuBarDisplayID ??
            mainDisplayID
    }
}
