//
//  MenuBarControlItemOrderPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Policy for keeping Continuum's structural menu-bar dividers in a valid
/// right-to-left order.
enum MenuBarControlItemOrderPolicy {
    static func requiresCorrection(
        hiddenBounds: CGRect,
        alwaysHiddenBounds: CGRect?
    ) -> Bool {
        guard let alwaysHiddenBounds else {
            return false
        }
        return hiddenBounds.maxX <= alwaysHiddenBounds.minX
    }

    static func correctionDestination(
        for controlItems: MenuBarControlItems
    ) -> MenuBarMoveDestination? {
        guard
            let alwaysHidden = controlItems.alwaysHidden,
            requiresCorrection(
                hiddenBounds: controlItems.hidden.bounds,
                alwaysHiddenBounds: alwaysHidden.bounds
            )
        else {
            return nil
        }

        return .leftOfItem(controlItems.hidden)
    }
}
