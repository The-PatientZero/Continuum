//
//  MenuBarNewItemsPlacementPreference.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Preference boundary for the user's chosen destination for newly seen items.
///
/// The manager owns the published value and performs UserDefaults I/O; this type
/// owns the persistence shape and legacy migration decision so startup/reset
/// behavior is explicit and independently testable.
enum MenuBarNewItemsPlacementPreference {
    typealias Placement = MenuBarNewItemsPlacement

    static let defaultPlacement = Placement.defaultValue

    static func load(
        encodedData: Data?,
        legacySectionKey: String?
    ) -> Placement {
        if let encodedData,
           let stored = try? JSONDecoder().decode(Placement.self, from: encodedData)
        {
            return stored
        }

        return legacyPlacement(sectionKey: legacySectionKey)
    }

    static func encodedData(for placement: Placement) -> Data? {
        try? JSONEncoder().encode(placement)
    }

    private static func legacyPlacement(sectionKey: String?) -> Placement {
        let persistedKey = sectionKey ?? Defaults.DefaultValue.newItemsSection
        let resolvedSection = MenuBarNewItemsPlacementPolicy.sectionName(for: persistedKey) ?? .hidden
        return Placement(
            sectionKey: MenuBarNewItemsPlacementPolicy.sectionKey(for: resolvedSection),
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
    }
}
