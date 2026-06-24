//
//  DisplayOverlayTrayConfiguration.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Per-display configuration for the Overlay Tray.
struct DisplayOverlayTrayConfiguration: Codable, Equatable {
    /// Whether the Overlay Tray is enabled on this display.
    let useOverlayTray: Bool

    /// The location where the Overlay Tray appears on this display.
    let overlayTrayLocation: OverlayTrayLocation

    /// Whether to always show hidden menu bar items on this display.
    ///
    /// This setting is only applicable when ``useOverlayTray`` is `false`.
    let alwaysShowHiddenItems: Bool

    /// The layout mode for the Overlay Tray on this display.
    let overlayTrayLayout: OverlayTrayLayout

    /// The maximum number of items per row when the Overlay Tray is in grid layout.
    ///
    /// Valid range is 2 through 10.
    let gridColumns: Int

    /// Default configuration (enabled, dynamic location, horizontal layout).
    static let defaultConfiguration = DisplayOverlayTrayConfiguration(
        useOverlayTray: true,
        overlayTrayLocation: .dynamic,
        alwaysShowHiddenItems: false,
        overlayTrayLayout: .horizontal,
        gridColumns: 4
    )

    /// Returns a new configuration with the `useOverlayTray` flag replaced.
    func withUseOverlayTray(_ value: Bool) -> DisplayOverlayTrayConfiguration {
        DisplayOverlayTrayConfiguration(
            useOverlayTray: value,
            overlayTrayLocation: overlayTrayLocation,
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            overlayTrayLayout: overlayTrayLayout,
            gridColumns: gridColumns
        )
    }

    /// Returns a new configuration with the `overlayTrayLocation` replaced.
    func withOverlayTrayLocation(_ value: OverlayTrayLocation) -> DisplayOverlayTrayConfiguration {
        DisplayOverlayTrayConfiguration(
            useOverlayTray: useOverlayTray,
            overlayTrayLocation: value,
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            overlayTrayLayout: overlayTrayLayout,
            gridColumns: gridColumns
        )
    }

    /// Returns a new configuration with the `alwaysShowHiddenItems` flag replaced.
    func withAlwaysShowHiddenItems(_ value: Bool) -> DisplayOverlayTrayConfiguration {
        DisplayOverlayTrayConfiguration(
            useOverlayTray: useOverlayTray,
            overlayTrayLocation: overlayTrayLocation,
            alwaysShowHiddenItems: value,
            overlayTrayLayout: overlayTrayLayout,
            gridColumns: gridColumns
        )
    }

    /// Returns a new configuration with the `overlayTrayLayout` replaced.
    func withOverlayTrayLayout(_ value: OverlayTrayLayout) -> DisplayOverlayTrayConfiguration {
        DisplayOverlayTrayConfiguration(
            useOverlayTray: useOverlayTray,
            overlayTrayLocation: overlayTrayLocation,
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            overlayTrayLayout: value,
            gridColumns: gridColumns
        )
    }

    /// Returns a new configuration with the `gridColumns` replaced.
    ///
    /// Values are clamped to the range 2 through 10.
    func withGridColumns(_ value: Int) -> DisplayOverlayTrayConfiguration {
        DisplayOverlayTrayConfiguration(
            useOverlayTray: useOverlayTray,
            overlayTrayLocation: overlayTrayLocation,
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            overlayTrayLayout: overlayTrayLayout,
            gridColumns: Swift.max(2, Swift.min(value, 10))
        )
    }

    /// Builds per-display configurations for all connected screens.
    @MainActor
    static func buildConfigurations(
        onlyOnNotched: Bool,
        location: OverlayTrayLocation
    ) -> [String: DisplayOverlayTrayConfiguration] {
        var configs = [String: DisplayOverlayTrayConfiguration]()
        for screen in NSScreen.managedScreens {
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else {
                continue
            }
            let enabled = onlyOnNotched ? screen.hasNotch : true
            configs[uuid] = DisplayOverlayTrayConfiguration(
                useOverlayTray: enabled,
                overlayTrayLocation: location,
                alwaysShowHiddenItems: false,
                overlayTrayLayout: .horizontal,
                gridColumns: 4
            )
        }
        return configs
    }
}

// MARK: - Backward-compatible decoding

extension DisplayOverlayTrayConfiguration {
    enum CodingKeys: String, CodingKey {
        case useOverlayTray
        case overlayTrayLocation
        case alwaysShowHiddenItems
        case overlayTrayLayout
        case gridColumns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.useOverlayTray = try container.decode(Bool.self, forKey: .useOverlayTray)
        self.overlayTrayLocation = try container.decode(OverlayTrayLocation.self, forKey: .overlayTrayLocation)
        self.alwaysShowHiddenItems = try container.decode(Bool.self, forKey: .alwaysShowHiddenItems)
        self.overlayTrayLayout = try container.decodeIfPresent(OverlayTrayLayout.self, forKey: .overlayTrayLayout) ?? .horizontal
        let decodedGridColumns = try container.decodeIfPresent(Int.self, forKey: .gridColumns) ?? 4
        self.gridColumns = Swift.max(2, Swift.min(decodedGridColumns, 10))
    }
}
