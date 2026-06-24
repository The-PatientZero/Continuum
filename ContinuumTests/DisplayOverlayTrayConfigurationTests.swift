//
//  DisplayOverlayTrayConfigurationTests.swift
//  Project: Continuum
//
//  Copyright © 2023-2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Continuum
import XCTest

final class DisplayOverlayTrayConfigurationTests: XCTestCase {
    func testDefaultConfiguration() {
        let config = DisplayOverlayTrayConfiguration.defaultConfiguration

        XCTAssertTrue(config.useOverlayTray)
        XCTAssertEqual(config.overlayTrayLocation, .dynamic)
        XCTAssertFalse(config.alwaysShowHiddenItems)
        XCTAssertEqual(config.overlayTrayLayout, .horizontal)
        XCTAssertEqual(config.gridColumns, 4)
    }

    func testCustomInitialization() {
        let config = DisplayOverlayTrayConfiguration(
            useOverlayTray: true,
            overlayTrayLocation: .mousePointer,
            alwaysShowHiddenItems: true,
            overlayTrayLayout: .grid,
            gridColumns: 6
        )

        XCTAssertTrue(config.useOverlayTray)
        XCTAssertEqual(config.overlayTrayLocation, .mousePointer)
        XCTAssertTrue(config.alwaysShowHiddenItems)
        XCTAssertEqual(config.overlayTrayLayout, .grid)
        XCTAssertEqual(config.gridColumns, 6)
    }

    func testWithMethodsDoNotMutateOriginal() {
        let original = DisplayOverlayTrayConfiguration.defaultConfiguration

        XCTAssertFalse(original.withUseOverlayTray(false).useOverlayTray)
        XCTAssertEqual(original.withOverlayTrayLocation(.controlIcon).overlayTrayLocation, .controlIcon)
        XCTAssertTrue(original.withAlwaysShowHiddenItems(true).alwaysShowHiddenItems)
        XCTAssertEqual(original.withOverlayTrayLayout(.vertical).overlayTrayLayout, .vertical)
        XCTAssertEqual(original.withGridColumns(8).gridColumns, 8)

        XCTAssertTrue(original.useOverlayTray)
        XCTAssertEqual(original.overlayTrayLocation, .dynamic)
        XCTAssertFalse(original.alwaysShowHiddenItems)
        XCTAssertEqual(original.overlayTrayLayout, .horizontal)
        XCTAssertEqual(original.gridColumns, 4)
    }

    func testGridColumnsClampToSupportedRange() {
        let original = DisplayOverlayTrayConfiguration.defaultConfiguration

        XCTAssertEqual(original.withGridColumns(0).gridColumns, 2)
        XCTAssertEqual(original.withGridColumns(20).gridColumns, 10)
        XCTAssertEqual(original.withGridColumns(5).gridColumns, 5)
    }

    func testChainedWithMethods() {
        let config = DisplayOverlayTrayConfiguration.defaultConfiguration
            .withUseOverlayTray(true)
            .withOverlayTrayLocation(.controlIcon)
            .withAlwaysShowHiddenItems(true)
            .withOverlayTrayLayout(.grid)
            .withGridColumns(5)

        XCTAssertTrue(config.useOverlayTray)
        XCTAssertEqual(config.overlayTrayLocation, .controlIcon)
        XCTAssertTrue(config.alwaysShowHiddenItems)
        XCTAssertEqual(config.overlayTrayLayout, .grid)
        XCTAssertEqual(config.gridColumns, 5)
    }

    func testEquatableIdentical() {
        let config1 = DisplayOverlayTrayConfiguration(
            useOverlayTray: true,
            overlayTrayLocation: .mousePointer,
            alwaysShowHiddenItems: false,
            overlayTrayLayout: .vertical,
            gridColumns: 3
        )
        let config2 = DisplayOverlayTrayConfiguration(
            useOverlayTray: true,
            overlayTrayLocation: .mousePointer,
            alwaysShowHiddenItems: false,
            overlayTrayLayout: .vertical,
            gridColumns: 3
        )

        XCTAssertEqual(config1, config2)
    }

    func testEquatableDifferences() {
        let config = DisplayOverlayTrayConfiguration.defaultConfiguration

        XCTAssertNotEqual(config, config.withUseOverlayTray(false))
        XCTAssertNotEqual(config, config.withOverlayTrayLocation(.controlIcon))
        XCTAssertNotEqual(config, config.withAlwaysShowHiddenItems(true))
        XCTAssertNotEqual(config, config.withOverlayTrayLayout(.grid))
        XCTAssertNotEqual(config, config.withGridColumns(6))
    }

    func testEncodeDecode() throws {
        let original = DisplayOverlayTrayConfiguration(
            useOverlayTray: true,
            overlayTrayLocation: .controlIcon,
            alwaysShowHiddenItems: true,
            overlayTrayLayout: .grid,
            gridColumns: 6
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DisplayOverlayTrayConfiguration.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testDecodeFromJSON() throws {
        let json = """
        {
            "useOverlayTray": true,
            "overlayTrayLocation": 2,
            "alwaysShowHiddenItems": false,
            "overlayTrayLayout": 2,
            "gridColumns": 5
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DisplayOverlayTrayConfiguration.self, from: json)

        XCTAssertTrue(decoded.useOverlayTray)
        XCTAssertEqual(decoded.overlayTrayLocation, .controlIcon)
        XCTAssertFalse(decoded.alwaysShowHiddenItems)
        XCTAssertEqual(decoded.overlayTrayLayout, .grid)
        XCTAssertEqual(decoded.gridColumns, 5)
    }

    func testDecodeOldJSONWithoutNewFields() throws {
        let json = """
        {
            "useOverlayTray": true,
            "overlayTrayLocation": 1,
            "alwaysShowHiddenItems": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DisplayOverlayTrayConfiguration.self, from: json)

        XCTAssertTrue(decoded.useOverlayTray)
        XCTAssertEqual(decoded.overlayTrayLocation, .mousePointer)
        XCTAssertFalse(decoded.alwaysShowHiddenItems)
        XCTAssertEqual(decoded.overlayTrayLayout, .horizontal)
        XCTAssertEqual(decoded.gridColumns, 4)
    }

    func testDecodeOldJSONWithInvalidGridColumns() throws {
        let json = """
        {
            "useOverlayTray": false,
            "overlayTrayLocation": 0,
            "alwaysShowHiddenItems": false,
            "overlayTrayLayout": 1,
            "gridColumns": 50
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DisplayOverlayTrayConfiguration.self, from: json)

        XCTAssertEqual(decoded.gridColumns, 10)
    }

    func testDecodeIgnoresLegacyItemSpacingOffset() throws {
        let json = """
        {
            "useOverlayTray": false,
            "overlayTrayLocation": 0,
            "alwaysShowHiddenItems": false,
            "overlayTrayLayout": 1,
            "gridColumns": 4,
            "itemSpacingOffset": 99
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DisplayOverlayTrayConfiguration.self, from: json)

        XCTAssertFalse(decoded.useOverlayTray)
        XCTAssertEqual(decoded.overlayTrayLocation, .dynamic)
        XCTAssertFalse(decoded.alwaysShowHiddenItems)
        XCTAssertEqual(decoded.overlayTrayLayout, .vertical)
        XCTAssertEqual(decoded.gridColumns, 4)
    }

    func testAllOverlayTrayLocations() {
        for location in OverlayTrayLocation.allCases {
            let config = DisplayOverlayTrayConfiguration.defaultConfiguration.withOverlayTrayLocation(location)
            XCTAssertEqual(config.overlayTrayLocation, location)
        }
    }

    func testAllOverlayTrayLayouts() {
        for layout in OverlayTrayLayout.allCases {
            let config = DisplayOverlayTrayConfiguration.defaultConfiguration.withOverlayTrayLayout(layout)
            XCTAssertEqual(config.overlayTrayLayout, layout)
        }
    }
}
