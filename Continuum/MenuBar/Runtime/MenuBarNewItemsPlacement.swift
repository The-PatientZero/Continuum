//
//  MenuBarNewItemsPlacement.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Persisted destination preference for newly detected menu bar items.
///
/// This value is part of the runtime planning contract. Keeping it outside the
/// manager lets badge placement, unmanaged-item planning, layout editing, and
/// preference migration share the same lightweight data model.
struct MenuBarNewItemsPlacement: Codable, Equatable {
    enum Relation: String, Codable {
        case leftOfAnchor
        case rightOfAnchor
        case sectionDefault
    }

    let sectionKey: String
    let anchorIdentifier: String?
    let relation: Relation

    static let defaultValue = MenuBarNewItemsPlacement(
        sectionKey: Defaults.DefaultValue.newItemsSection,
        anchorIdentifier: nil,
        relation: .sectionDefault
    )
}
