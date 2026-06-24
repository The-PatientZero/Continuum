//
//  OnboardingSlide.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A single page of the onboarding tour, in the order it's presented.
enum OnboardingSlide: Int, CaseIterable, Identifiable {
    case welcome
    case menuBarManagement
    case permissions

    static let allCases: [Self] = [
        .welcome,
        .menuBarManagement,
        .permissions,
    ]

    var id: Int {
        rawValue
    }

    /// The slide's headline, shown beneath its mockup.
    var title: LocalizedStringResource {
        switch self {
        case .welcome: "Welcome to Continuum"
        case .menuBarManagement: "Menu Bar Management"
        case .permissions: "Permissions"
        }
    }

    /// The slide's body copy, shown beneath its title.
    var description: LocalizedStringResource {
        switch self {
        case .welcome:
            "Continuum keeps your menu bar quiet: tuck away the icons you do not need, then reveal them when you do."
        case .menuBarManagement:
            "Move items between visible and hidden sections, then use the menu bar control to show or rehide them on demand."
        case .permissions:
            "Continuum uses Accessibility to identify menu bar items and move them after you save a layout. Items may appear as Menu Extra until macOS reports their owner."
        }
    }
}
