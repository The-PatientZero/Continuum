//
//  HotkeyAction.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

enum HotkeyAction: String, Codable, CaseIterable {
    // Menu Bar Sections
    case toggleHiddenSection = "ToggleHiddenSection"
    case toggleAlwaysHiddenSection = "ToggleAlwaysHiddenSection"

    // Other
    case enableOverlayTray = "EnableOverlayTray"
    case toggleApplicationMenus = "ToggleApplicationMenus"

    /// Used by per-item hotkeys, action is handled externally.
    case openMenuBarItem = "OpenMenuBarItem"

    /// Built-in singleton actions. Dynamic per-item hotkeys are created
    /// separately and are excluded here.
    static var settingsActions: [HotkeyAction] {
        [.toggleHiddenSection]
    }

    @MainActor
    func perform(appState: AppState) {
        switch self {
        case .toggleHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            section.toggle(triggeredByHotkey: true)
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.menuBarManager.showOnHoverAllowed = false
            }
        case .toggleAlwaysHiddenSection:
            break
        case .enableOverlayTray:
            break
        case .toggleApplicationMenus:
            break
        case .openMenuBarItem:
            // Handled externally by MenuBarManager's per-item registration.
            break
        }
    }
}
