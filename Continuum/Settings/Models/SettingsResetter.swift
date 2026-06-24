//
//  SettingsResetter.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

extension AppSettings {
    /// Resets all settings to their default values.
    func resetAllSettingsToDefaults() {
        resetGeneral()
        resetAdvanced()
        resetHotkeys()
        resetDisplay()
    }

    /// Resets General settings to their default values.
    func resetGeneral() {
        general.showControlIcon = Defaults.DefaultValue.showControlIcon
        general.controlIcon = Defaults.DefaultValue.controlIcon
        general.lastCustomControlIcon = nil
        general.customControlIconIsTemplate = Defaults.DefaultValue.customControlIconIsTemplate
        general.useOverlayTray = Defaults.DefaultValue.useOverlayTray
        general.useOverlayTrayOnlyOnNotchedDisplay = Defaults.DefaultValue.useOverlayTrayOnlyOnNotchedDisplay
        general.overlayTrayLocation = Defaults.DefaultValue.overlayTrayLocation
        general.overlayTrayLocationOnHotkey = Defaults.DefaultValue.overlayTrayLocationOnHotkey
        general.showOnClick = Defaults.DefaultValue.showOnClick
        general.showOnDoubleClick = Defaults.DefaultValue.showOnDoubleClick
        general.showOnHover = Defaults.DefaultValue.showOnHover
        general.showOnScroll = Defaults.DefaultValue.showOnScroll
        general.autoRehide = Defaults.DefaultValue.autoRehide
        general.rehideStrategy = Defaults.DefaultValue.rehideStrategy
        general.rehideInterval = Defaults.DefaultValue.rehideInterval
    }

    /// Resets Advanced settings to their default values.
    func resetAdvanced() {
        advanced.enableAlwaysHiddenSection = Defaults.DefaultValue.enableAlwaysHiddenSection
        advanced.showAllSectionsOnUserDrag = Defaults.DefaultValue.showAllSectionsOnUserDrag
        appState?.itemManager.updateNewItemsPlacement(section: .hidden, arrangedViews: [])
        advanced.sectionDividerStyle = Defaults.DefaultValue.sectionDividerStyle
        advanced.hideApplicationMenus = Defaults.DefaultValue.hideApplicationMenus
        advanced.enableSecondaryContextMenu = Defaults.DefaultValue.enableSecondaryContextMenu
        advanced.showOnHoverDelay = Defaults.DefaultValue.showOnHoverDelay
        advanced.tooltipDelay = Defaults.DefaultValue.tooltipDelay
        advanced.showMenuBarTooltips = Defaults.DefaultValue.showMenuBarTooltips
        advanced.iconRefreshInterval = Defaults.DefaultValue.iconRefreshInterval
        advanced.enableDiagnosticLogging = Defaults.DefaultValue.enableDiagnosticLogging
    }

    /// Resets Hotkeys settings to their default values.
    func resetHotkeys() {
        Defaults.set(Defaults.DefaultValue.hotkeys, forKey: .hotkeys)
        for hotkey in hotkeys.hotkeys {
            hotkey.keyCombination = nil
        }
    }

    /// Resets Display settings to their default values.
    func resetDisplay() {
        displaySettings.configurations = Defaults.DefaultValue.displayOverlayTrayConfigurations
    }
}
