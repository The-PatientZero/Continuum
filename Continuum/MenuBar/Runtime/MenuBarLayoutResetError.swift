//
//  MenuBarLayoutResetError.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Error boundary for layout reset recovery.
///
/// Reset failures are runtime-health failures: the app state or the section
/// control items needed to perform a stable reset are unavailable. Keeping the
/// cases outside the manager makes reset recovery explicit and testable.
enum MenuBarLayoutResetError: LocalizedError {
    case missingAppState
    case missingControlItems

    var errorDescription: String? {
        switch self {
        case .missingAppState:
            "Unable to access app state"
        case .missingControlItems:
            "Couldn't find section dividers in the menu bar"
        }
    }

    var recoverySuggestion: String? {
        "Make sure \(Constants.displayName) is running and try again."
    }
}
