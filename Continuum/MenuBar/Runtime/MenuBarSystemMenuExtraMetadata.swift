//
//  MenuBarSystemMenuExtraMetadata.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Resolves stable display metadata for macOS system menu extras.
///
/// Window Server observations for Control Center and SystemUIServer items are
/// often sparse or generic. This resolver gives the runtime one tested mapping
/// for names and SF Symbols used by both Settings and the overlay tray.
enum MenuBarSystemMenuExtraMetadata {
    static func displayName(for item: MenuBarItem) -> String? {
        displayName(
            namespace: item.tag.namespace.description,
            title: item.title ?? item.controlCenterModuleTitle ?? item.tag.title
        )
    }

    static func displayName(namespace: String, title: String) -> String? {
        // No blanket empty-title guard: several system agents (Screen Sharing,
        // Input Menu, Game Mode, etc.) own a single menu bar window that the
        // Window Server frequently reports with an empty title. Those are
        // matched by namespace wildcard below and must resolve even when the
        // title is empty. The title-dependent fallthrough cases guard against
        // empty titles individually.
        switch (namespace, title) {
        case ("com.apple.controlcenter", "BentoBox-0"):
            return "Control Center"
        case ("com.apple.controlcenter", "WiFi"):
            return "Wi-Fi"
        case ("com.apple.controlcenter", "NowPlaying"):
            return "Now Playing"
        case ("com.apple.controlcenter", "ScreenMirroring"):
            return "Screen Mirroring"
        case ("com.apple.controlcenter", "MusicRecognition"):
            return "Music Recognition"
        case ("com.apple.controlcenter", "AudioVideoModule"):
            return "Camera & Microphone"
        case ("com.apple.controlcenter", "AccessibilityShortcuts"):
            return "Accessibility Shortcuts"
        case ("com.apple.controlcenter", "FocusModes"):
            return "Focus"
        case ("com.apple.controlcenter", "UserSwitcher"):
            return "Fast User Switching"
        case ("com.apple.systemuiserver", "com.apple.menuextra.TimeMachine"):
            return "Time Machine"
        case ("com.apple.systemuiserver", "Siri"):
            return "Siri"
        case ("com.apple.TextInputMenuAgent", _):
            return "Input Menu"
        case ("com.apple.SSMenuAgent", _):
            return "Screen Sharing"
        case ("GamePolicyAgent", _):
            return "Game Mode"
        case ("com.apple.weather.menu", _):
            return "Weather"
        case ("com.apple.Passwords.MenuBarExtra", _):
            return "Passwords"
        case ("com.apple.screencaptureui", _):
            return "Screen Recording"
        case ("com.apple.controlcenter", let controlCenterTitle):
            guard !controlCenterTitle.isEmpty,
                  !MarkerPairResolver.isGenericControlCenterTitle(controlCenterTitle)
            else { return nil }
            return readableSystemTitle(controlCenterTitle)
        case ("com.apple.systemuiserver", let systemTitle):
            guard !systemTitle.isEmpty else { return nil }
            return readableSystemTitle(systemTitle.replacingOccurrences(of: "com.apple.menuextra.", with: ""))
        default:
            return nil
        }
    }

    static func symbolName(for item: MenuBarItem) -> String? {
        symbolName(
            namespace: item.tag.namespace.description,
            title: item.title ?? item.controlCenterModuleTitle ?? item.tag.title
        )
    }

    static func symbolName(forSavedIdentifier identifier: String) -> String? {
        let parts = identifier.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        return symbolName(namespace: String(parts[0]), title: String(parts[1]))
    }

    static func symbolName(namespace: String, title: String) -> String? {
        switch (namespace, title) {
        case ("com.apple.controlcenter", "BentoBox-0"):
            return "slider.horizontal.3"
        case ("com.apple.controlcenter", "WiFi"):
            return "wifi"
        case ("com.apple.controlcenter", "Bluetooth"):
            return "dot.radiowaves.left.and.right"
        case ("com.apple.controlcenter", "Battery"):
            return "battery.100"
        case ("com.apple.controlcenter", "Clock"):
            return "clock"
        case ("com.apple.controlcenter", "Sound"),
             ("com.apple.controlcenter", "Volume"):
            return "speaker.wave.2"
        case ("com.apple.controlcenter", "Display"):
            return "display"
        case ("com.apple.controlcenter", "ScreenMirroring"):
            return "rectangle.on.rectangle"
        case ("com.apple.controlcenter", "NowPlaying"),
             ("com.apple.controlcenter", "MusicRecognition"):
            return "music.note"
        case ("com.apple.controlcenter", "AudioVideoModule"),
             ("com.apple.controlcenter", "FaceTime"):
            return "video"
        case ("com.apple.controlcenter", "Hearing"):
            return "ear"
        case ("com.apple.controlcenter", "FocusModes"):
            return "moon"
        case ("com.apple.controlcenter", "AccessibilityShortcuts"):
            return "accessibility"
        case ("com.apple.controlcenter", "UserSwitcher"):
            return "person.crop.circle"
        case ("com.apple.systemuiserver", "com.apple.menuextra.TimeMachine"):
            return "clock.arrow.circlepath"
        case ("com.apple.systemuiserver", "Siri"):
            return "sparkles"
        case ("com.apple.TextInputMenuAgent", _):
            return "keyboard"
        case ("com.apple.SSMenuAgent", _):
            return "rectangle.on.rectangle"
        case ("GamePolicyAgent", _):
            return "gamecontroller"
        case ("com.apple.weather.menu", _):
            return "cloud.sun"
        case ("com.apple.Passwords.MenuBarExtra", _):
            return "key"
        case ("com.apple.screencaptureui", _):
            return "record.circle"
        case ("com.apple.controlcenter", let controlCenterTitle):
            return MarkerPairResolver.isGenericControlCenterTitle(controlCenterTitle) ? nil : "slider.horizontal.3"
        case ("com.apple.systemuiserver", _):
            return "gearshape"
        default:
            return nil
        }
    }

    private static func readableSystemTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacing(/([a-z]{2})([A-Z])/) { "\($0.output.1) \($0.output.2)" }
    }
}
