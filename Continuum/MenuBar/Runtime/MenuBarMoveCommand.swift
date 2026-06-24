//
//  MenuBarMoveCommand.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Immutable command envelope for one menu bar item move.
///
/// This keeps command shape and retry policy out of the live CGEvent path so
/// the runtime can test move decisions without posting events.
struct MenuBarMoveCommand {
    let item: MenuBarItem
    let destination: MenuBarMoveDestination
    let displayID: CGDirectDisplayID?
    let skipInputPause: Bool
    let watchdogTimeout: DispatchTimeInterval?
    let maxMoveAttempts: Int

    var normalizedMaxAttempts: Int {
        max(1, maxMoveAttempts)
    }

    var relation: MenuBarMovePreflight.Relation {
        switch destination {
        case .leftOfItem:
            .leftOfItem
        case .rightOfItem:
            .rightOfItem
        }
    }

    var diagnosticDescription: String {
        "\(item.logString) -> \(destination.logString)"
    }

    func preflight(isBlocked: Bool) -> MenuBarMovePreflight.Decision {
        MenuBarMovePreflight.evaluate(
            item: item,
            relation: relation,
            isBlocked: isBlocked
        )
    }

    func acceptsPositionMatch(
        atAttempt attempt: Int,
        observedDisplacement: Bool
    ) -> Bool {
        attempt == 1 || observedDisplacement || !item.isControlItem
    }

    func shouldRetry(afterAttempt attempt: Int) -> Bool {
        attempt < normalizedMaxAttempts
    }

    func placementVerification(
        expectedSection: MenuBarSection.Name,
        cache: MenuBarItemCache
    ) -> MenuBarMoveVerification.Outcome {
        MenuBarMoveVerification.evaluate(
            item: item,
            destination: destination,
            expectedSection: expectedSection,
            cache: cache
        )
    }

    func didReachDestination(
        expectedSection: MenuBarSection.Name,
        cache: MenuBarItemCache
    ) -> Bool {
        placementVerification(
            expectedSection: expectedSection,
            cache: cache
        ).didReachDestination
    }
}
