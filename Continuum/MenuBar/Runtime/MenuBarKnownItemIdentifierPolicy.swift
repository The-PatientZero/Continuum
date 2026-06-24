//
//  MenuBarKnownItemIdentifierPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure policy for deciding which observed menu bar item identifiers are safe
/// to remember across cache cycles.
enum MenuBarKnownItemIdentifierPolicy {
    static func persistableBaseIdentifier(for item: MenuBarItem) -> String? {
        guard !item.isControlItem, item.identityConfidence.allowsPersistence else {
            return nil
        }
        return "\(item.tag.namespace):\(item.tag.title)"
    }

    static func persistableBaseIdentifiers(from items: [MenuBarItem]) -> Set<String> {
        Set(items.compactMap(persistableBaseIdentifier(for:)))
    }

    static func identifiersToSeedAfterIdentityCorrection(
        observation: MenuBarObservationFrame,
        previousWindowIDs: [CGWindowID],
        knownItemIdentifiers: Set<String>
    ) -> Set<String> {
        guard !previousWindowIDs.isEmpty else {
            return []
        }

        return observation
            .persistableIdentifiersForPreviouslySeenWindows(previousWindowIDs)
            .subtracting(knownItemIdentifiers)
    }
}
