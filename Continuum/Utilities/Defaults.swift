//
//  Defaults.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI

enum Defaults {
    /// Returns a dictionary containing the keys and values for
    /// the defaults meant to be seen by all applications.
    static var globalDomain: [String: Any] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
    }

    /// Returns the object for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func object(forKey key: Key) -> Any? {
        UserDefaults.standard.object(forKey: key.rawValue)
    }

    /// Returns the string for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func string(forKey key: Key) -> String? {
        UserDefaults.standard.string(forKey: key.rawValue)
    }

    /// Returns the array for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func array(forKey key: Key) -> [Any]? {
        UserDefaults.standard.array(forKey: key.rawValue)
    }

    /// Returns the dictionary for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func dictionary(forKey key: Key) -> [String: Any]? {
        UserDefaults.standard.dictionary(forKey: key.rawValue)
    }

    /// Returns the data for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func data(forKey key: Key) -> Data? {
        UserDefaults.standard.data(forKey: key.rawValue)
    }

    /// Returns the string array for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func stringArray(forKey key: Key) -> [String]? {
        UserDefaults.standard.stringArray(forKey: key.rawValue)
    }

    /// Returns the integer value for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func integer(forKey key: Key) -> Int {
        UserDefaults.standard.integer(forKey: key.rawValue)
    }

    /// Returns the single precision floating point value for
    /// the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func float(forKey key: Key) -> Float {
        UserDefaults.standard.float(forKey: key.rawValue)
    }

    /// Returns the double precision floating point value for
    /// the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func double(forKey key: Key) -> Double {
        UserDefaults.standard.double(forKey: key.rawValue)
    }

    /// Returns the Boolean value for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func bool(forKey key: Key) -> Bool {
        UserDefaults.standard.bool(forKey: key.rawValue)
    }

    /// Returns the url for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func url(forKey key: Key) -> URL? {
        UserDefaults.standard.url(forKey: key.rawValue)
    }

    /// Sets the value for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to set the value for.
    static func set(_ value: Any?, forKey key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    /// Removes the value of the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to remove the value for.
    static func removeObject(forKey key: Key) {
        UserDefaults.standard.removeObject(forKey: key.rawValue)
    }

    /// Retrieves the value for the given key, and, if it is
    /// present, assigns it to the given `inout` parameter.
    static func ifPresent<Value>(key: Key, assign value: inout Value) {
        if let found = object(forKey: key) as? Value {
            value = found
        }
    }

    /// Retrieves the value for the given key, and, if it is
    /// present, performs the given closure.
    static func ifPresent<Value>(key: Key, body: (Value) throws -> Void) rethrows {
        if let found = object(forKey: key) as? Value {
            try body(found)
        }
    }
}

extension Defaults {
    enum DefaultValue {
        // MARK: General Settings

        static let showControlIcon = true
        static let controlIcon = ControlItemImageSet.defaultControlIcon
        static let customControlIconIsTemplate = false
        static let useOverlayTray = true
        static let useOverlayTrayOnlyOnNotchedDisplay = false
        static let overlayTrayLocation: OverlayTrayLocation = .dynamic
        static let overlayTrayLocationOnHotkey = false
        static let showOnClick = true
        static let showOnDoubleClick = false
        static let showOnHover = false
        static let showOnScroll = false
        static let autoRehide = true
        static let rehideStrategy: RehideStrategy = .smart
        static let rehideInterval: TimeInterval = 15

        // MARK: Advanced Settings

        static let enableAlwaysHiddenSection = false
        static let showAllSectionsOnUserDrag = true
        static let newItemsSection = "hidden"
        static let newItemsPlacementData: Data? = nil
        static let sectionDividerStyle: SectionDividerStyle = .noDivider
        static let hideApplicationMenus = false
        static let enableSecondaryContextMenu = false
        static let enableSecondaryContextMenuQuit = false
        static let showOnHoverDelay: TimeInterval = 0.2
        static let tooltipDelay: TimeInterval = 0.5
        static let showMenuBarTooltips = false
        static let iconRefreshInterval: TimeInterval = 1.0
        #if DEBUG
            static let enableDiagnosticLogging = true
        #else
            static let enableDiagnosticLogging = false
        #endif
        static let useLCSSortingOnNotchedDisplays = true
        static let useOptionClickToShowAlwaysHiddenSection = false
        static let useDoubleClickToShowAlwaysHiddenSection = false
        static let enableMenuBarItemOverflow = false

        // MARK: Hotkeys Settings

        static nonisolated(unsafe) let hotkeys: [Any]? = nil

        // MARK: Display Settings

        static let displayOverlayTrayConfigurations: [String: DisplayOverlayTrayConfiguration] = [:]
    }
}

extension Defaults {
    enum Key: String {
        // MARK: General Settings

        case showControlIcon = "ShowControlIcon"
        case controlIcon = "ControlIcon"
        case customControlIconIsTemplate = "CustomControlIconIsTemplate"
        case useOverlayTray = "UseOverlayTray"
        case useOverlayTrayOnlyOnNotchedDisplay = "UseOverlayTrayOnlyOnNotchedDisplay"
        case overlayTrayLocation = "OverlayTrayLocation"
        case overlayTrayLocationOnHotkey = "OverlayTrayLocationOnHotkey"
        case showOnClick = "ShowOnClick"
        case showOnDoubleClick = "ShowOnDoubleClick"
        case showOnHover = "ShowOnHover"
        case showOnScroll = "ShowOnScroll"
        case autoRehide = "AutoRehide"
        case rehideStrategy = "RehideStrategy"
        case rehideInterval = "RehideInterval"
        case displayOverlayTrayConfigurations = "DisplayOverlayTrayConfigurations"

        // MARK: Hotkeys Settings

        case hotkeys = "Hotkeys"
        case menuBarItemHotkeys = "MenuBarItemHotkeys"

        // MARK: Advanced Settings

        case enableAlwaysHiddenSection = "EnableAlwaysHiddenSection"
        case showAllSectionsOnUserDrag = "ShowAllSectionsOnUserDrag"
        case newItemsSection = "NewItemsSection"
        case newItemsPlacementData = "NewItemsPlacementData"
        case sectionDividerStyle = "SectionDividerStyle"
        case hideApplicationMenus = "HideApplicationMenus"
        case enableSecondaryContextMenu = "EnableSecondaryContextMenu"
        case enableSecondaryContextMenuQuit = "EnableSecondaryContextMenuQuit"
        case showOnHoverDelay = "ShowOnHoverDelay"
        case tooltipDelay = "TooltipDelay"
        case iconRefreshInterval = "IconRefreshInterval"
        case showMenuBarTooltips = "ShowMenuBarTooltips"
        case enableDiagnosticLogging = "EnableDiagnosticLogging"
        case useLCSSortingOnNotchedDisplays = "UseLCSSortingOnNotchedDisplays"
        case useOptionClickToShowAlwaysHiddenSection = "UseOptionClickToShowAlwaysHiddenSection"
        case useDoubleClickToShowAlwaysHiddenSection = "UseDoubleClickToShowAlwaysHiddenSection"
        case enableMenuBarItemOverflow = "EnableMenuBarItemOverflow"

        // MARK: Menu Bar Item Custom Names

        case menuBarItemCustomNames = "MenuBarItemCustomNames"

        // MARK: Migration

        case hasMigrated0_8_0
        case hasMigrated0_10_0
        case hasMigrated0_10_1
        case hasMigrated0_11_10
        case hasMigrated0_11_13
        case hasMigrated0_11_13_1
        case hasMigratedPerDisplayOverlayTray

        // MARK: First Launch

        case hasCompletedFirstLaunch

        // MARK: Updates Consent

        case hasSeenUpdateConsent

        // MARK: Onboarding

        case hasSeenOnboarding

        // MARK: Deprecated (Advanced Settings)

        case showSectionDividers = "ShowSectionDividers"
        case canToggleAlwaysHiddenSection = "CanToggleAlwaysHiddenSection"

        // MARK: Deprecated (Other)

        case sections = "Sections"
    }
}
