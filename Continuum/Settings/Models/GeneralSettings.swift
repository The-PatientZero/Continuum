//
//  GeneralSettings.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

// MARK: - GeneralSettings

/// Model for the app's General settings.
@MainActor
final class GeneralSettings: ObservableObject {
    private let diagLog = DiagLog(category: "GeneralSettings")
    /// A Boolean value that indicates whether the control icon
    /// should be shown.
    @Published var showControlIcon = Defaults.DefaultValue.showControlIcon

    /// An icon to show in the menu bar, with a different image
    /// for when items are visible or hidden.
    @Published var controlIcon = Defaults.DefaultValue.controlIcon

    /// The last user-selected custom control icon.
    @Published var lastCustomControlIcon: ControlItemImageSet?

    /// A Boolean value that indicates whether custom control icons
    /// should be rendered as template images.
    @Published var customControlIconIsTemplate = Defaults.DefaultValue.customControlIconIsTemplate

    // MARK: - Minimal Runtime Defaults

    /// A Boolean value that indicates whether to show hidden items
    /// in a separate bar below the menu bar.
    @Published var useOverlayTray = Defaults.DefaultValue.useOverlayTray

    /// A Boolean value that indicates whether to use the Overlay Tray
    /// only on displays with a notch.
    @Published var useOverlayTrayOnlyOnNotchedDisplay = Defaults.DefaultValue.useOverlayTrayOnlyOnNotchedDisplay

    /// The location where the Overlay Tray appears.
    @Published var overlayTrayLocation = Defaults.DefaultValue.overlayTrayLocation

    /// A Boolean value that indicates whether the Overlay Tray should
    /// appear at the mouse pointer's location when shown by a hotkey.
    @Published var overlayTrayLocationOnHotkey = Defaults.DefaultValue.overlayTrayLocationOnHotkey

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer clicks in an empty
    /// area of the menu bar.
    @Published var showOnClick = Defaults.DefaultValue.showOnClick

    /// A Boolean value that indicates whether the always-hidden section
    /// should be shown when the mouse pointer double-clicks in an
    /// empty area of the menu bar.
    @Published var showOnDoubleClick = Defaults.DefaultValue.showOnDoubleClick

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer hovers over an
    /// empty area of the menu bar.
    @Published var showOnHover = Defaults.DefaultValue.showOnHover

    /// A Boolean value that indicates whether the hidden section
    /// should be shown or hidden when the user scrolls in the
    /// menu bar.
    @Published var showOnScroll = Defaults.DefaultValue.showOnScroll

    // The offset to apply to the menu bar item spacing and padding.

    /// A Boolean value that indicates whether the hidden section
    /// should automatically rehide.
    @Published var autoRehide = Defaults.DefaultValue.autoRehide

    /// A strategy that determines how the auto-rehide feature works.
    @Published var rehideStrategy = Defaults.DefaultValue.rehideStrategy

    /// A time interval for the auto-rehide feature when its rule
    /// is ``RehideStrategy/timed``.
    @Published var rehideInterval = Defaults.DefaultValue.rehideInterval

    /// Encoder for properties.
    private let encoder = JSONEncoder()

    /// Decoder for properties.
    private let decoder = JSONDecoder()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureCancellables()
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        Defaults.ifPresent(key: .showControlIcon, assign: &showControlIcon)
        Defaults.ifPresent(key: .customControlIconIsTemplate, assign: &customControlIconIsTemplate)

        if let data = Defaults.data(forKey: .controlIcon) {
            do {
                controlIcon = try decoder.decode(ControlItemImageSet.self, from: data)
            } catch {
                diagLog.error("Error decoding \(Constants.displayName) icon: \(error)")
            }
            if case .custom = controlIcon.name {
                lastCustomControlIcon = controlIcon
            }
        }
    }

    /// Configures the internal observers for the model.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $showControlIcon.persistToDefaults(key: .showControlIcon, in: &c)

        // controlIcon requires encoding + custom icon tracking - keep manual
        $controlIcon
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] controlIcon in
                guard let self else {
                    return
                }
                if case .custom = controlIcon.name {
                    lastCustomControlIcon = controlIcon
                }
                do {
                    let data = try encoder.encode(controlIcon)
                    Defaults.set(data, forKey: .controlIcon)
                } catch {
                    diagLog.error("Error encoding \(Constants.displayName) icon: \(error)")
                }
            }
            .store(in: &c)

        $customControlIconIsTemplate.persistToDefaults(key: .customControlIconIsTemplate, in: &c)
        $useOverlayTray.persistToDefaults(key: .useOverlayTray, in: &c)
        $useOverlayTrayOnlyOnNotchedDisplay.persistToDefaults(key: .useOverlayTrayOnlyOnNotchedDisplay, in: &c)
        $overlayTrayLocation.persistToDefaults(key: .overlayTrayLocation, transform: \.rawValue, in: &c)
        $overlayTrayLocationOnHotkey.persistToDefaults(key: .overlayTrayLocationOnHotkey, in: &c)
        $showOnClick.persistToDefaults(key: .showOnClick, in: &c)
        $showOnDoubleClick.persistToDefaults(key: .showOnDoubleClick, in: &c)
        $showOnHover.persistToDefaults(key: .showOnHover, in: &c)
        $showOnScroll.persistToDefaults(key: .showOnScroll, in: &c)
        $autoRehide.persistToDefaults(key: .autoRehide, in: &c)
        $rehideStrategy.persistToDefaults(key: .rehideStrategy, transform: \.rawValue, in: &c)
        $rehideInterval.persistToDefaults(key: .rehideInterval, in: &c)

        cancellables = c
    }
}
