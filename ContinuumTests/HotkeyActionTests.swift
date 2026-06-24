//
//  HotkeyActionTests.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Continuum
import XCTest

final class HotkeyActionTests: XCTestCase {
    // MARK: - Raw Value Tests

    func testRawValues() {
        XCTAssertEqual(HotkeyAction.toggleHiddenSection.rawValue, "ToggleHiddenSection")
        XCTAssertEqual(HotkeyAction.toggleAlwaysHiddenSection.rawValue, "ToggleAlwaysHiddenSection")
        XCTAssertEqual(HotkeyAction.enableOverlayTray.rawValue, "EnableOverlayTray")
        XCTAssertEqual(HotkeyAction.toggleApplicationMenus.rawValue, "ToggleApplicationMenus")
        XCTAssertEqual(HotkeyAction.openMenuBarItem.rawValue, "OpenMenuBarItem")
    }

    // MARK: - Init from Raw Value Tests

    func testInitFromRawValue() {
        XCTAssertEqual(HotkeyAction(rawValue: "ToggleHiddenSection"), .toggleHiddenSection)
    }

    func testInitFromInvalidRawValue() {
        XCTAssertNil(HotkeyAction(rawValue: "InvalidAction"))
        XCTAssertNil(HotkeyAction(rawValue: ""))
        XCTAssertNil(HotkeyAction(rawValue: "togglehiddensection")) // case-sensitive
    }

    // MARK: - CaseIterable Tests

    func testAllCasesCount() {
        XCTAssertEqual(HotkeyAction.allCases.count, 5)
    }

    func testAllCasesContainsExpectedActions() {
        let allCases = HotkeyAction.allCases
        XCTAssertTrue(allCases.contains(.toggleHiddenSection))
        XCTAssertTrue(allCases.contains(.toggleAlwaysHiddenSection))
        XCTAssertTrue(allCases.contains(.enableOverlayTray))
        XCTAssertTrue(allCases.contains(.toggleApplicationMenus))
        XCTAssertTrue(allCases.contains(.openMenuBarItem))
    }

    // MARK: - Settings Actions Tests

    func testSettingsActionsExcludesOpenMenuBarItem() {
        let settingsActions = HotkeyAction.settingsActions
        XCTAssertFalse(settingsActions.contains(.openMenuBarItem))
    }

    func testSettingsActionsContainsOnlyMinimalRuntimeAction() {
        let settingsActions = HotkeyAction.settingsActions
        XCTAssertEqual(settingsActions, [.toggleHiddenSection])
    }

    func testSettingsActionsCount() {
        XCTAssertEqual(HotkeyAction.settingsActions.count, 1)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for action in HotkeyAction.allCases {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(HotkeyAction.self, from: data)
            XCTAssertEqual(decoded, action)
        }
    }

    func testDecodeFromStringJSON() throws {
        let json = "\"ToggleHiddenSection\"".data(using: .utf8)!
        let decoder = JSONDecoder()

        let decoded = try decoder.decode(HotkeyAction.self, from: json)
        XCTAssertEqual(decoded, .toggleHiddenSection)
    }
}
