//
//  SettingsNavigationIdentifier.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The navigation identifier type for the "Settings" interface.
enum SettingsNavigationIdentifier: String, NavigationIdentifier {
    case general = "General"
    case layout = "Layout"
    case about = "About"

    static let visibleCases: [Self] = [
        .general,
        .layout,
        .about,
    ]

    var localized: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .layout: "Layout"
        case .about: "About"
        }
    }

    var iconResource: IconResource {
        switch self {
        case .general: .systemSymbol("gearshape")
        case .layout: .systemSymbol("rectangle.3.group")
        case .about: .systemSymbol("cube")
        }
    }
}
