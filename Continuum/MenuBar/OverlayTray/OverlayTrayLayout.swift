//
//  OverlayTrayLayout.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Layout modes for the Overlay Tray.
enum OverlayTrayLayout: Int, CaseIterable, Codable, Identifiable {
    /// Items are arranged in a single horizontal row.
    case horizontal = 0

    /// Items are stacked vertically in a single column.
    case vertical = 1

    /// Items are arranged in a grid with a configurable number of columns.
    case grid = 2

    var id: Int {
        rawValue
    }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        case .grid: "Grid"
        }
    }

    /// Parses an OverlayTrayLayout from a string value.
    /// Supports exact case names: "horizontal", "vertical", "grid"
    /// Or raw integer values: "0", "1", "2"
    static func fromString(_ value: String) -> OverlayTrayLayout? {
        switch value {
        case "horizontal", "0":
            return .horizontal
        case "vertical", "1":
            return .vertical
        case "grid", "2":
            return .grid
        default:
            return nil
        }
    }
}
