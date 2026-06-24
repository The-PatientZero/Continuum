//
//  MenuBarSystemMenuExtraMetadata.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

struct MenuBarSystemMenuExtraIcon: Hashable {
    enum Source: Hashable {
        case systemSymbol(String)
        case appKitImage(String)
        case bundleImage(bundlePath: String, resourceName: String)
    }

    let source: Source
    let fallbackSystemSymbolName: String?

    init(source: Source, fallbackSystemSymbolName: String? = nil) {
        self.source = source
        self.fallbackSystemSymbolName = fallbackSystemSymbolName
    }

    var systemSymbolName: String? {
        if case let .systemSymbol(name) = source {
            return name
        }
        return fallbackSystemSymbolName
    }

    var nsImage: NSImage? {
        let image: NSImage? = switch source {
        case let .systemSymbol(name):
            NSImage(systemSymbolName: name, accessibilityDescription: nil)
        case let .appKitImage(name):
            NSImage(named: NSImage.Name(name))
        case let .bundleImage(bundlePath, resourceName):
            Bundle(url: URL(fileURLWithPath: bundlePath))?.image(forResource: resourceName)
        }

        guard let copy = image?.copy() as? NSImage else {
            return nil
        }
        copy.isTemplate = true
        return copy
    }
}

/// Resolves stable display metadata for macOS system menu extras.
///
/// Window Server observations for Control Center and SystemUIServer items are
/// often sparse or generic. This resolver gives the runtime one tested mapping
/// for names and native glyphs used by both Settings and the overlay tray.
enum MenuBarSystemMenuExtraMetadata {
    private static let controlCenterBundlePath = "/System/Library/CoreServices/ControlCenter.app"

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
        case let ("com.apple.controlcenter", controlCenterTitle):
            guard !controlCenterTitle.isEmpty,
                  !MarkerPairResolver.isGenericControlCenterTitle(controlCenterTitle)
            else { return nil }
            return readableSystemTitle(controlCenterTitle)
        case let ("com.apple.systemuiserver", systemTitle):
            guard !systemTitle.isEmpty else { return nil }
            return readableSystemTitle(systemTitle.replacingOccurrences(of: "com.apple.menuextra.", with: ""))
        default:
            return nil
        }
    }

    static func symbolName(for item: MenuBarItem) -> String? {
        icon(
            namespace: item.tag.namespace.description,
            title: item.title ?? item.controlCenterModuleTitle ?? item.tag.title
        )?.systemSymbolName
    }

    static func symbolName(forSavedIdentifier identifier: String) -> String? {
        let parts = identifier.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        return symbolName(namespace: String(parts[0]), title: String(parts[1]))
    }

    static func symbolName(namespace: String, title: String) -> String? {
        icon(namespace: namespace, title: title)?.systemSymbolName
    }

    static func icon(for item: MenuBarItem) -> MenuBarSystemMenuExtraIcon? {
        icon(
            namespace: item.tag.namespace.description,
            title: item.title ?? item.controlCenterModuleTitle ?? item.tag.title
        )
    }

    static func icon(forSavedIdentifier identifier: String) -> MenuBarSystemMenuExtraIcon? {
        let parts = identifier.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        return icon(namespace: String(parts[0]), title: String(parts[1]))
    }

    static func icon(namespace: String, title: String) -> MenuBarSystemMenuExtraIcon? {
        switch (namespace, title) {
        case ("com.apple.controlcenter", "BentoBox-0"):
            return .init(source: .systemSymbol("switch.2"))
        case ("com.apple.controlcenter", "WiFi"):
            return controlCenterImage("wifi.menu.network", fallbackSystemSymbolName: "wifi")
        case ("com.apple.controlcenter", "Bluetooth"):
            return .init(
                source: .appKitImage("NSBluetoothTemplate"),
                fallbackSystemSymbolName: "dot.radiowaves.left.and.right"
            )
        case ("com.apple.controlcenter", "Battery"):
            return controlCenterImage("battery-outline", fallbackSystemSymbolName: "battery.100")
        case ("com.apple.controlcenter", "Clock"):
            return .init(source: .systemSymbol("clock"))
        case ("com.apple.controlcenter", "Sound"),
             ("com.apple.controlcenter", "Volume"):
            return .init(source: .systemSymbol("speaker.wave.2"))
        case ("com.apple.controlcenter", "Display"):
            return .init(source: .systemSymbol("display"))
        case ("com.apple.controlcenter", "ScreenMirroring"):
            return .init(source: .systemSymbol("rectangle.on.rectangle"))
        case ("com.apple.controlcenter", "NowPlaying"),
             ("com.apple.controlcenter", "MusicRecognition"):
            return .init(source: .systemSymbol("music.note"))
        case ("com.apple.controlcenter", "AudioVideoModule"),
             ("com.apple.controlcenter", "FaceTime"):
            return .init(source: .systemSymbol("video"))
        case ("com.apple.controlcenter", "Hearing"):
            return .init(source: .systemSymbol("ear"))
        case ("com.apple.controlcenter", "FocusModes"):
            return .init(source: .systemSymbol("moon"))
        case ("com.apple.controlcenter", "AccessibilityShortcuts"):
            return .init(source: .systemSymbol("accessibility"))
        case ("com.apple.controlcenter", "UserSwitcher"):
            return .init(source: .systemSymbol("person.crop.circle"))
        case ("com.apple.controlcenter", "AirDrop"):
            return .init(source: .systemSymbol("airplayaudio"))
        case ("com.apple.controlcenter", "KeyboardBrightness"):
            return .init(source: .systemSymbol("keyboard"))
        case ("com.apple.systemuiserver", "com.apple.menuextra.TimeMachine"):
            return .init(source: .systemSymbol("clock.arrow.circlepath"))
        case ("com.apple.systemuiserver", "Siri"):
            return .init(source: .systemSymbol("sparkles"))
        case ("com.apple.TextInputMenuAgent", _):
            return .init(source: .systemSymbol("keyboard"))
        case ("com.apple.SSMenuAgent", _):
            return .init(source: .systemSymbol("rectangle.on.rectangle"))
        case ("GamePolicyAgent", _):
            return .init(source: .systemSymbol("gamecontroller"))
        case ("com.apple.weather.menu", _):
            return .init(source: .systemSymbol("cloud.sun"))
        case ("com.apple.Passwords.MenuBarExtra", _):
            return .init(source: .systemSymbol("key"))
        case ("com.apple.screencaptureui", _):
            return .init(source: .systemSymbol("record.circle"))
        case let ("com.apple.controlcenter", controlCenterTitle):
            return MarkerPairResolver.isGenericControlCenterTitle(controlCenterTitle)
                ? nil
                : .init(source: .systemSymbol("switch.2"))
        case ("com.apple.systemuiserver", _):
            return .init(source: .systemSymbol("gearshape"))
        default:
            return nil
        }
    }

    private static func controlCenterImage(
        _ resourceName: String,
        fallbackSystemSymbolName: String
    ) -> MenuBarSystemMenuExtraIcon {
        .init(
            source: .bundleImage(bundlePath: controlCenterBundlePath, resourceName: resourceName),
            fallbackSystemSymbolName: fallbackSystemSymbolName
        )
    }

    private static func readableSystemTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacing(/([a-z]{2})([A-Z])/) { "\($0.output.1) \($0.output.2)" }
    }
}
