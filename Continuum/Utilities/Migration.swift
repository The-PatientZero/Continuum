//
//  Migration.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// FIXME: Migration has gotten extremely messy. It should really just be completely redone at this point.
// TODO: Decide what needs to stay in the new implementation, and what has been around long enough that it can be removed.
@MainActor
struct MigrationManager {
    private let diagLog = DiagLog(category: "Migration")

    let appState: AppState
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
}

// MARK: - Migrate All

extension MigrationManager {
    /// Performs all migrations.
    func migrateAll() {
        var results = [MigrationResult]()

        do {
            try performAll(blocks: [
                migrateForRelease080,
                migrateForRelease0100,
            ])
        } catch let error as MigrationError {
            results.append(.failureAndLogError(error))
        } catch {
            diagLog.error("Migration failed with unknown error \(error)")
        }

        results += [
            migrateForRelease0101(),
            migrateForRelease01110(),
            migrateForRelease01113(),
            migrateForRelease011131(),
            migratePerDisplayOverlayTray(),
        ]

        for result in results {
            switch result {
            case .success:
                continue
            case let .successButShowAlert(alert):
                alert.runModal()
            case let .failureAndLogError(error):
                diagLog.error("Migration failed with error \(error)")
            }
        }
    }
}

// MARK: - Migrate 0.8.0

extension MigrationManager {
    /// Performs all migrations for the `0.8.0` release, catching any thrown
    /// errors and rethrowing them as a combined error.
    private func migrateForRelease080() throws {
        guard !Defaults.bool(forKey: .hasMigrated0_8_0) else {
            return
        }
        try performAll(blocks: [
            migrateHotkeysForRelease080,
            migrateControlItemsForRelease080,
            migrateSectionsForRelease080,
        ])
        Defaults.set(true, forKey: .hasMigrated0_8_0)
        diagLog.info("Successfully migrated to 0.8.0 settings")
    }

    // MARK: Migrate Hotkeys

    /// Migrates the user's saved hotkeys from the old method of storing
    /// them in their corresponding menu bar sections to the new method
    /// of storing them as stand-alone data in the `0.8.0` release.
    private func migrateHotkeysForRelease080() throws {
        let sectionsArray: [[String: Any]]
        do {
            guard let array = try getMenuBarSectionArray() else {
                return
            }
            sectionsArray = array
        } catch {
            throw MigrationError.hotkeyMigrationError(error)
        }

        // get the hotkey data from the hidden and always-hidden sections,
        // if available, and create equivalent key combinations to assign
        // to the corresponding hotkeys
        for name: MenuBarSection.Name in [.hidden, .alwaysHidden] {
            guard
                let sectionDict = sectionsArray.first(where: { $0["name"] as? String == name.rawValue0_8_0 }),
                let hotkeyDict = sectionDict["hotkey"] as? [String: Int],
                let key = hotkeyDict["key"],
                let modifiers = hotkeyDict["modifiers"]
            else {
                continue
            }
            let keyCombination = KeyCombination(
                key: KeyCode(rawValue: key),
                modifiers: Modifiers(rawValue: modifiers)
            )
            let hotkeysSettings = appState.settings.hotkeys
            if case .hidden = name,
               let hotkey = hotkeysSettings.hotkey(withAction: .toggleHiddenSection)
            {
                hotkey.keyCombination = keyCombination
            } else if case .alwaysHidden = name,
                      let hotkey = hotkeysSettings.hotkey(withAction: .toggleAlwaysHiddenSection)
            {
                hotkey.keyCombination = keyCombination
            }
        }
    }

    // MARK: Migrate Control Items

    /// Migrates the control items from their old serialized representations
    /// to their new representations in the `0.8.0` release.
    private func migrateControlItemsForRelease080() throws {
        let sectionsArray: [[String: Any]]
        do {
            guard let array = try getMenuBarSectionArray() else {
                return
            }
            sectionsArray = array
        } catch {
            throw MigrationError.controlItemMigrationError(error)
        }

        var newSectionsArray = [[String: Any]]()

        for name in MenuBarSection.Name.allCases {
            guard
                var sectionDict = sectionsArray.first(where: { $0["name"] as? String == name.rawValue0_8_0 }),
                var controlItemDict = sectionDict["controlItem"] as? [String: Any],
                // remove the "autosaveName" key from the dictionary
                let autosaveName = controlItemDict.removeValue(forKey: "autosaveName") as? String
            else {
                continue
            }

            let identifier = switch name {
            case .visible:
                ControlItem.Identifier.visible.rawValue0_8_0
            case .hidden:
                ControlItem.Identifier.hidden.rawValue0_8_0
            case .alwaysHidden:
                ControlItem.Identifier.alwaysHidden.rawValue0_8_0
            }

            // add the "identifier" key to the dictionary
            controlItemDict["identifier"] = identifier

            // migrate the old autosave name to the new autosave name in UserDefaults
            ControlItemDefaults.migrate(key: .preferredPosition, from: autosaveName, to: identifier)
            ControlItemDefaults.migrate(key: .visible, from: autosaveName, to: identifier)

            // replace the old "controlItem" dictionary with the new one
            sectionDict["controlItem"] = controlItemDict
            // add the section to the new array
            newSectionsArray.append(sectionDict)
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: newSectionsArray)
            Defaults.set(data, forKey: .sections)
        } catch {
            throw MigrationError.controlItemMigrationError(error)
        }
    }

    /// Migrates away from storing the menu bar sections in UserDefaults
    /// for the `0.8.0` release.
    private func migrateSectionsForRelease080() {
        Defaults.set(nil, forKey: .sections)
    }
}

// MARK: - Migrate 0.10.0

extension MigrationManager {
    /// Performs all migrations for the `0.10.0` release.
    private func migrateForRelease0100() {
        guard !Defaults.bool(forKey: .hasMigrated0_10_0) else {
            return
        }

        migrateControlItemsForRelease0100()

        Defaults.set(true, forKey: .hasMigrated0_10_0)
        diagLog.info("Successfully migrated to 0.10.0 settings")
    }

    private func migrateControlItemsForRelease0100() {
        for identifier in ControlItem.Identifier.allCases {
            ControlItemDefaults.migrate(
                key: .preferredPosition,
                from: identifier.rawValue0_8_0,
                to: identifier.rawValue0_10_0
            )
        }
    }
}

// MARK: - Migrate 0.10.1

extension MigrationManager {
    /// Performs all migrations for the `0.10.1` release.
    private func migrateForRelease0101() -> MigrationResult {
        guard !Defaults.bool(forKey: .hasMigrated0_10_1) else {
            return .success
        }
        let result = migrateControlItemsForRelease0101()
        switch result {
        case .success, .successButShowAlert:
            Defaults.set(true, forKey: .hasMigrated0_10_1)
            diagLog.info("Successfully migrated to 0.10.1 settings")
        case .failureAndLogError:
            break
        }
        return result
    }

    private func migrateControlItemsForRelease0101() -> MigrationResult {
        var needsResetPreferredPositions = false

        for identifier in ControlItem.Identifier.allCases {
            if
                ControlItemDefaults[.visible, identifier.rawValue0_10_0] == false,
                ControlItemDefaults[.preferredPosition, identifier.rawValue0_10_0] == nil
            {
                needsResetPreferredPositions = true
            }
            ControlItemDefaults[.visible, identifier.rawValue0_10_0] = nil
        }

        if needsResetPreferredPositions {
            for identifier in ControlItem.Identifier.allCases {
                ControlItemDefaults[.preferredPosition, identifier.rawValue0_10_0] = nil
            }

            let alert = NSAlert()
            alert.messageText = String(localized: "Due to a bug in a previous version of the app, the data for \(Constants.displayName)'s menu bar sections was corrupted and had to be reset.")

            return .successButShowAlert(alert)
        }

        return .success
    }
}

// MARK: - Migrate 0.11.10

extension MigrationManager {
    /// Performs all migrations for the `0.11.10` release.
    private func migrateForRelease01110() -> MigrationResult {
        guard !Defaults.bool(forKey: .hasMigrated0_11_10) else {
            return .success
        }
        Defaults.set(true, forKey: .hasMigrated0_11_10)
        diagLog.info("Successfully migrated to 0.11.10 settings")
        return .success
    }
}

// MARK: - Migrate 0.11.13

extension MigrationManager {
    /// Performs all migrations for the `0.11.13` release.
    private func migrateForRelease01113() -> MigrationResult {
        guard !Defaults.bool(forKey: .hasMigrated0_11_13) else {
            return .success
        }

        migrateSectionDividersForRelease01113()

        Defaults.set(true, forKey: .hasMigrated0_11_13)
        diagLog.info("Successfully migrated to 0.11.13 settings")

        return .success
    }

    private func migrateSectionDividersForRelease01113() {
        let style = if Defaults.bool(forKey: .showSectionDividers) {
            SectionDividerStyle.chevron
        } else {
            SectionDividerStyle.noDivider
        }
        Defaults.set(style.rawValue, forKey: .sectionDividerStyle)
        Defaults.removeObject(forKey: .showSectionDividers)
    }
}

// MARK: - Migrate 0.11.13.1

extension MigrationManager {
    /// Performs all migrations for the `0.11.13.1` release.
    private func migrateForRelease011131() -> MigrationResult {
        guard !Defaults.bool(forKey: .hasMigrated0_11_13_1) else {
            return .success
        }

        migrateControlItemsForRelease011131()

        Defaults.set(true, forKey: .hasMigrated0_11_13_1)
        diagLog.info("Successfully migrated to 0.11.13.1 settings")

        return .success
    }

    private func migrateControlItemsForRelease011131() {
        for identifier in ControlItem.Identifier.allCases {
            ControlItemDefaults.migrate(
                key: .preferredPosition,
                from: identifier.rawValue0_10_0,
                to: identifier.rawValue
            )
            ControlItemDefaults.migrate(
                key: .visible,
                from: identifier.rawValue0_10_0,
                to: identifier.rawValue
            )
            ControlItemDefaults.migrate(
                key: .visibleCC,
                from: identifier.rawValue0_10_0,
                to: identifier.rawValue
            )
        }
    }
}

// MARK: - Migrate Per-Display Overlay Tray

extension MigrationManager {
    /// Migrates legacy global Overlay Tray settings to per-display configurations.
    private func migratePerDisplayOverlayTray() -> MigrationResult {
        guard !Defaults.bool(forKey: .hasMigratedPerDisplayOverlayTray) else {
            return .success
        }

        let useOverlayTray = Defaults.bool(forKey: .useOverlayTray)
        let useOnlyOnNotched = Defaults.bool(forKey: .useOverlayTrayOnlyOnNotchedDisplay)
        let overlayTrayLocationRaw = Defaults.integer(forKey: .overlayTrayLocation)
        let overlayTrayLocation = OverlayTrayLocation(rawValue: overlayTrayLocationRaw) ?? .dynamic

        // Only create per-display configs if the user had Overlay Tray enabled.
        guard useOverlayTray else {
            Defaults.set(true, forKey: .hasMigratedPerDisplayOverlayTray)
            diagLog.info("Per-display Overlay Tray migration: Overlay Tray was disabled, nothing to migrate")
            return .success
        }

        let configs = DisplayOverlayTrayConfiguration.buildConfigurations(
            onlyOnNotched: useOnlyOnNotched,
            location: overlayTrayLocation
        )

        do {
            let data = try encoder.encode(configs)
            Defaults.set(data, forKey: .displayOverlayTrayConfigurations)
            Defaults.set(true, forKey: .hasMigratedPerDisplayOverlayTray)
            diagLog.info("Per-display Overlay Tray migration: migrated \(configs.count) display(s)")
        } catch {
            return .failureAndLogError(.perDisplayOverlayTrayMigrationError(error))
        }

        return .success
    }
}

// MARK: - Helpers

extension MigrationManager {
    /// Performs every block in the given array, catching any thrown
    /// errors and rethrowing them as a combined error.
    private func performAll(blocks: [() throws -> Void]) throws {
        let results = blocks.map { block in
            Result(catching: block)
        }
        let errors = results.compactMap { result in
            if case let .failure(error) = result {
                return error
            }
            return nil
        }
        if !errors.isEmpty {
            throw MigrationError.combinedError(errors)
        }
    }

    /// Returns an array of dictionaries that represent the sections in
    /// the menu bar, as stored in UserDefaults.
    private func getMenuBarSectionArray() throws -> [[String: Any]]? {
        guard let data = Defaults.data(forKey: .sections) else {
            return nil
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let array = object as? [[String: Any]] else {
            throw MigrationError.invalidMenuBarSectionsJSONObject(String(describing: object))
        }
        return array
    }
}

// MARK: - MigrationResult

extension MigrationManager {
    enum MigrationResult {
        case success
        case successButShowAlert(NSAlert)
        case failureAndLogError(MigrationError)
    }
}

// MARK: - MigrationError

extension MigrationManager {
    enum MigrationError: Error, CustomStringConvertible {
        case invalidMenuBarSectionsJSONObject(String)
        case hotkeyMigrationError(any Error)
        case controlItemMigrationError(any Error)
        case perDisplayOverlayTrayMigrationError(any Error)
        case combinedError([any Error])

        var description: String {
            switch self {
            case let .invalidMenuBarSectionsJSONObject(object):
                "Invalid menu bar sections JSON object: \(object)"
            case let .hotkeyMigrationError(error):
                "Error migrating hotkeys: \(error)"
            case let .controlItemMigrationError(error):
                "Error migrating control items: \(error)"
            case let .perDisplayOverlayTrayMigrationError(error):
                "Error migrating per-display Overlay Tray configuration: \(error)"
            case let .combinedError(errors):
                "The following errors occurred: \(errors)"
            }
        }
    }
}

// MARK: - ControlItem.Identifier Extension

private extension ControlItem.Identifier {
    var rawValue0_8_0: String {
        switch self {
        case .visible: "ControlIcon"
        case .hidden: "HItem"
        case .alwaysHidden: "AHItem"
        }
    }

    var rawValue0_10_0: String {
        switch self {
        case .visible: "SItem"
        case .hidden: "HItem"
        case .alwaysHidden: "AHItem"
        }
    }
}

// MARK: - MenuBarSection.Name Extension

private extension MenuBarSection.Name {
    var rawValue0_8_0: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }
}
