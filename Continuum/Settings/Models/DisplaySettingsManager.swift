//
//  DisplaySettingsManager.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine

/// Manages per-display Overlay Tray configuration.
///
/// Configurations are keyed by display UUID string (via `Bridging.getDisplayUUIDString(for:)`).
/// When a display has no explicit configuration, `DisplayOverlayTrayConfiguration.defaultConfiguration`
/// is returned.
@MainActor
final class DisplaySettingsManager: ObservableObject {
    private let diagLog = DiagLog(category: "DisplaySettingsManager")

    /// Per-display configurations, keyed by display UUID string.
    @Published var configurations: [String: DisplayOverlayTrayConfiguration] = [:]

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// JSON encoder for persistence.
    private let encoder = JSONEncoder()

    /// JSON decoder for persistence.
    private let decoder = JSONDecoder()

    /// Performs the initial setup of the manager.
    func performSetup(with _: AppState) {
        loadInitialState()
        configureCancellables()
    }

    // MARK: - Loading

    /// Loads saved configurations from Defaults.
    private func loadInitialState() {
        guard let data = Defaults.data(forKey: .displayOverlayTrayConfigurations) else {
            return
        }

        do {
            configurations = try decoder.decode([String: DisplayOverlayTrayConfiguration].self, from: data)
            diagLog.info("Loaded per-display configurations for \(configurations.count) display(s)")
        } catch {
            diagLog.error("Failed to decode per-display configurations: \(error)")
        }
    }

    // MARK: - Persistence

    /// Configures Combine sinks to persist configurations on change.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $configurations
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] configs in
                guard let self else { return }
                do {
                    let data = try encoder.encode(configs)
                    Defaults.set(data, forKey: .displayOverlayTrayConfigurations)
                } catch {
                    diagLog.error("Failed to encode per-display configurations: \(error)")
                }
            }
            .store(in: &c)

        cancellables = c
    }

    // MARK: - Lookup

    /// Returns the configuration for a given display ID.
    func configuration(for displayID: CGDirectDisplayID) -> DisplayOverlayTrayConfiguration {
        guard let uuid = Bridging.getDisplayUUIDString(for: displayID) else {
            return .defaultConfiguration
        }
        return configurations[uuid] ?? .defaultConfiguration
    }

    /// Returns the configuration for the display with the active menu bar.
    func configurationForActiveDisplay() -> DisplayOverlayTrayConfiguration {
        guard let displayID = Bridging.getActiveMenuBarDisplayID() else {
            return .defaultConfiguration
        }
        return configuration(for: displayID)
    }

    /// Whether the Overlay Tray is enabled for the given display.
    func useOverlayTray(for displayID: CGDirectDisplayID) -> Bool {
        configuration(for: displayID).useOverlayTray
    }

    /// The Overlay Tray location for the given display.
    func overlayTrayLocation(for displayID: CGDirectDisplayID) -> OverlayTrayLocation {
        configuration(for: displayID).overlayTrayLocation
    }

    /// The Overlay Tray layout for the given display.
    func overlayTrayLayout(for displayID: CGDirectDisplayID) -> OverlayTrayLayout {
        configuration(for: displayID).overlayTrayLayout
    }

    /// The grid column count for the given display.
    func gridColumns(for displayID: CGDirectDisplayID) -> Int {
        configuration(for: displayID).gridColumns
    }

    /// Whether hidden items should always be shown for the given display.
    func alwaysShowHiddenItems(for displayID: CGDirectDisplayID) -> Bool {
        configuration(for: displayID).alwaysShowHiddenItems
    }

    /// Whether any connected display has "Always show hidden items" enabled.
    var isAlwaysShowEnabledOnAnyDisplay: Bool {
        configurations.values.contains { $0.alwaysShowHiddenItems }
    }
}
