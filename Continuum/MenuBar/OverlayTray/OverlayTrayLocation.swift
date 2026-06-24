//
//  OverlayTrayLocation.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Locations where the Overlay Tray can appear.
enum OverlayTrayLocation: Int, CaseIterable, Codable, Identifiable {
    /// The Overlay Tray will appear in different locations based on context.
    case dynamic = 0

    /// The Overlay Tray will appear centered below the mouse pointer.
    case mousePointer = 1

    /// The Overlay Tray will appear centered below the control icon.
    case controlIcon = 2

    /// The Overlay Tray will appear aligned to the left edge of the display.
    case leftAligned = 3

    /// The Overlay Tray will appear aligned to the right edge of the display.
    case rightAligned = 4

    var id: Int {
        rawValue
    }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .dynamic: "Dynamic"
        case .mousePointer: "Mouse pointer"
        case .controlIcon: "\(Constants.displayName) icon"
        case .leftAligned: "Left aligned"
        case .rightAligned: "Right aligned"
        }
    }

    /// Parses an OverlayTrayLocation from a string value.
    /// Supports exact case names: "dynamic", "mousePointer", "controlIcon"
    /// Or raw integer values: "0", "1", "2"
    static func fromString(_ value: String) -> OverlayTrayLocation? {
        switch value {
        case "dynamic", "0":
            return .dynamic
        case "mousePointer", "1":
            return .mousePointer
        case "controlIcon", "2":
            return .controlIcon
        case "leftAligned", "3":
            return .leftAligned
        case "rightAligned", "4":
            return .rightAligned
        default:
            return nil
        }
    }
}
