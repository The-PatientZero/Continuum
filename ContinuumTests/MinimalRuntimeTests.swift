//
//  MinimalRuntimeTests.swift
//  Project: Continuum
//
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Continuum
import AppKit
import XCTest

@MainActor
final class MinimalRuntimeTests: XCTestCase {
    func testScreenRecordingIsNotRequestedForMinimalRuntime() {
        let permissions = AppPermissions()

        XCTAssertEqual(permissions.allPermissions.map(\.title), ["Accessibility"])
        XCTAssertTrue(permissions.requiredPermissions.allSatisfy(\.isRequired))
    }

    func testMenuBarImageCaptureIsDisabled() {
        XCTAssertFalse(MenuBarItemImageCache.capturesScreenContent)
    }

    func testMenuBarImageCacheIsPassive() async {
        let cache = MenuBarItemImageCache()

        XCTAssertTrue(cache.images.isEmpty)
        XCTAssertNil(cache.image(for: .hiddenControlItem))
        XCTAssertFalse(cache.cacheFailed(for: .hidden))

        cache.markSettingsPaneOpened()
        cache.setItemHotkeyListExpanded(true)
        await cache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        await cache.updateCache(sections: MenuBarSection.Name.allCases)
        await cache.updateCache()
        cache.performCacheCleanup()

        XCTAssertTrue(cache.settingsPaneHasBeenOpened)
        XCTAssertTrue(cache.isItemHotkeyListExpanded)
        XCTAssertTrue(cache.images.isEmpty)
        XCTAssertEqual(cache.cacheSize, 0)
        XCTAssertEqual(cache.lruEntryCount, 0)
    }

    func testOverlayTrayColorManagerDoesNotSampleScreen() {
        let manager = OverlayTrayColorManager()
        XCTAssertNil(manager.colorInfo)

        if let screen = NSScreen.main {
            manager.updateAllProperties(with: .zero, screen: screen)
            XCTAssertNil(manager.colorInfo)
        }
    }

    func testManagedScreensUsesPlainSystemEnumeration() {
        XCTAssertEqual(
            NSScreen.managedScreens.map(\.displayID),
            NSScreen.screens.map(\.displayID)
        )
    }

    func testSettingsNavigationOnlyShowsMinimalProductSurface() {
        XCTAssertEqual(SettingsNavigationIdentifier.visibleCases, [.general, .layout, .about])
    }

    func testMinimalRuntimeDefaultsAvoidExtraGlobalTriggers() {
        XCTAssertTrue(Defaults.DefaultValue.showOnClick)
        XCTAssertTrue(Defaults.DefaultValue.useOverlayTray)
        XCTAssertTrue(DisplayOverlayTrayConfiguration.defaultConfiguration.useOverlayTray)
        XCTAssertFalse(Defaults.DefaultValue.showOnDoubleClick)
        XCTAssertFalse(Defaults.DefaultValue.showOnHover)
        XCTAssertFalse(Defaults.DefaultValue.showOnScroll)
        XCTAssertFalse(Defaults.DefaultValue.hideApplicationMenus)
        XCTAssertFalse(Defaults.DefaultValue.enableSecondaryContextMenu)
        XCTAssertFalse(Defaults.DefaultValue.enableMenuBarItemOverflow)
        XCTAssertEqual(Defaults.DefaultValue.iconRefreshInterval, 1.0)
    }

    func testLegacyGeneralDefaultsCannotReenableRemovedInteractionModes() {
        let legacyKeys: [Defaults.Key] = [
            .useOverlayTray,
            .useOverlayTrayOnlyOnNotchedDisplay,
            .overlayTrayLocation,
            .overlayTrayLocationOnHotkey,
            .showOnClick,
            .showOnDoubleClick,
            .showOnHover,
            .showOnScroll,
            .autoRehide,
            .rehideStrategy,
            .rehideInterval,
        ]
        legacyKeys.forEach { Defaults.removeObject(forKey: $0) }
        defer { legacyKeys.forEach { Defaults.removeObject(forKey: $0) } }

        Defaults.set(false, forKey: .useOverlayTray)
        Defaults.set(true, forKey: .useOverlayTrayOnlyOnNotchedDisplay)
        Defaults.set(OverlayTrayLocation.rightAligned.rawValue, forKey: .overlayTrayLocation)
        Defaults.set(true, forKey: .overlayTrayLocationOnHotkey)
        Defaults.set(false, forKey: .showOnClick)
        Defaults.set(true, forKey: .showOnDoubleClick)
        Defaults.set(true, forKey: .showOnHover)
        Defaults.set(true, forKey: .showOnScroll)
        Defaults.set(false, forKey: .autoRehide)
        Defaults.set(RehideStrategy.focusedApp.rawValue, forKey: .rehideStrategy)
        Defaults.set(120.0, forKey: .rehideInterval)

        let appState = AppState()
        let settings = GeneralSettings()
        settings.performSetup(with: appState)

        XCTAssertTrue(settings.useOverlayTray)
        XCTAssertFalse(settings.useOverlayTrayOnlyOnNotchedDisplay)
        XCTAssertEqual(settings.overlayTrayLocation, .dynamic)
        XCTAssertFalse(settings.overlayTrayLocationOnHotkey)
        XCTAssertTrue(settings.showOnClick)
        XCTAssertFalse(settings.showOnDoubleClick)
        XCTAssertFalse(settings.showOnHover)
        XCTAssertFalse(settings.showOnScroll)
        XCTAssertTrue(settings.autoRehide)
        XCTAssertEqual(settings.rehideStrategy, .smart)
        XCTAssertEqual(settings.rehideInterval, 15)
    }

    func testLegacyAdvancedDefaultsOnlyRestoreLayoutOwnedAlwaysHiddenSection() {
        let legacyKeys: [Defaults.Key] = [
            .enableAlwaysHiddenSection,
            .useOptionClickToShowAlwaysHiddenSection,
            .useDoubleClickToShowAlwaysHiddenSection,
            .showAllSectionsOnUserDrag,
            .sectionDividerStyle,
            .hideApplicationMenus,
            .enableSecondaryContextMenu,
            .enableSecondaryContextMenuQuit,
            .showOnHoverDelay,
            .tooltipDelay,
            .showMenuBarTooltips,
            .iconRefreshInterval,
            .useLCSSortingOnNotchedDisplays,
            .enableMenuBarItemOverflow,
        ]
        legacyKeys.forEach { Defaults.removeObject(forKey: $0) }
        defer { legacyKeys.forEach { Defaults.removeObject(forKey: $0) } }

        Defaults.set(true, forKey: .enableAlwaysHiddenSection)
        Defaults.set(true, forKey: .useOptionClickToShowAlwaysHiddenSection)
        Defaults.set(true, forKey: .useDoubleClickToShowAlwaysHiddenSection)
        Defaults.set(false, forKey: .showAllSectionsOnUserDrag)
        Defaults.set(SectionDividerStyle.chevron.rawValue, forKey: .sectionDividerStyle)
        Defaults.set(true, forKey: .hideApplicationMenus)
        Defaults.set(true, forKey: .enableSecondaryContextMenu)
        Defaults.set(true, forKey: .enableSecondaryContextMenuQuit)
        Defaults.set(3.0, forKey: .showOnHoverDelay)
        Defaults.set(3.0, forKey: .tooltipDelay)
        Defaults.set(true, forKey: .showMenuBarTooltips)
        Defaults.set(30.0, forKey: .iconRefreshInterval)
        Defaults.set(false, forKey: .useLCSSortingOnNotchedDisplays)
        Defaults.set(true, forKey: .enableMenuBarItemOverflow)

        let appState = AppState()
        let settings = AdvancedSettings()
        settings.performSetup(with: appState)

        XCTAssertTrue(settings.enableAlwaysHiddenSection)
        XCTAssertFalse(settings.useOptionClickToShowAlwaysHiddenSection)
        XCTAssertFalse(settings.useDoubleClickToShowAlwaysHiddenSection)
        XCTAssertTrue(settings.showAllSectionsOnUserDrag)
        XCTAssertEqual(settings.sectionDividerStyle, .noDivider)
        XCTAssertFalse(settings.hideApplicationMenus)
        XCTAssertFalse(settings.enableSecondaryContextMenu)
        XCTAssertFalse(settings.enableSecondaryContextMenuQuit)
        XCTAssertEqual(settings.showOnHoverDelay, 0.2)
        XCTAssertEqual(settings.tooltipDelay, 0.5)
        XCTAssertFalse(settings.showMenuBarTooltips)
        XCTAssertEqual(settings.iconRefreshInterval, 1.0)
        XCTAssertTrue(settings.useLCSSortingOnNotchedDisplays)
        XCTAssertFalse(settings.enableMenuBarItemOverflow)
    }
}
