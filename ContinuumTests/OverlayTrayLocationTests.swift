//
//  OverlayTrayLocationTests.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Continuum
import XCTest

final class OverlayTrayLocationTests: XCTestCase {
    // MARK: - Raw Value Tests

    func testDynamicRawValue() {
        XCTAssertEqual(OverlayTrayLocation.dynamic.rawValue, 0)
    }

    func testMousePointerRawValue() {
        XCTAssertEqual(OverlayTrayLocation.mousePointer.rawValue, 1)
    }

    func testControlIconRawValue() {
        XCTAssertEqual(OverlayTrayLocation.controlIcon.rawValue, 2)
    }

    func testLeftAlignedRawValue() {
        XCTAssertEqual(OverlayTrayLocation.leftAligned.rawValue, 3)
    }

    func testRightAlignedRawValue() {
        XCTAssertEqual(OverlayTrayLocation.rightAligned.rawValue, 4)
    }

    // MARK: - Init from Raw Value Tests

    func testInitFromRawValueZero() {
        XCTAssertEqual(OverlayTrayLocation(rawValue: 0), .dynamic)
    }

    func testInitFromRawValueOne() {
        XCTAssertEqual(OverlayTrayLocation(rawValue: 1), .mousePointer)
    }

    func testInitFromRawValueTwo() {
        XCTAssertEqual(OverlayTrayLocation(rawValue: 2), .controlIcon)
    }

    func testInitFromRawValueThree() {
        XCTAssertEqual(OverlayTrayLocation(rawValue: 3), .leftAligned)
    }

    func testInitFromRawValueFour() {
        XCTAssertEqual(OverlayTrayLocation(rawValue: 4), .rightAligned)
    }

    func testInitFromInvalidRawValue() {
        XCTAssertNil(OverlayTrayLocation(rawValue: -1))
        XCTAssertNil(OverlayTrayLocation(rawValue: 100))
    }

    // MARK: - Identifiable Tests

    func testIdMatchesRawValue() {
        for location in OverlayTrayLocation.allCases {
            XCTAssertEqual(location.id, location.rawValue)
        }
    }

    // MARK: - CaseIterable Tests

    func testAllCasesCount() {
        XCTAssertEqual(OverlayTrayLocation.allCases.count, 5)
    }

    func testAllCasesContainsAllLocations() {
        XCTAssertTrue(OverlayTrayLocation.allCases.contains(.dynamic))
        XCTAssertTrue(OverlayTrayLocation.allCases.contains(.mousePointer))
        XCTAssertTrue(OverlayTrayLocation.allCases.contains(.controlIcon))
        XCTAssertTrue(OverlayTrayLocation.allCases.contains(.leftAligned))
        XCTAssertTrue(OverlayTrayLocation.allCases.contains(.rightAligned))
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for location in OverlayTrayLocation.allCases {
            let data = try encoder.encode(location)
            let decoded = try decoder.decode(OverlayTrayLocation.self, from: data)
            XCTAssertEqual(decoded, location)
        }
    }

    func testDecodeFromRawValueJSON() throws {
        let decoder = JSONDecoder()

        // JSON integers should decode to locations
        XCTAssertEqual(try decoder.decode(OverlayTrayLocation.self, from: XCTUnwrap("0".data(using: .utf8))), .dynamic)
        XCTAssertEqual(try decoder.decode(OverlayTrayLocation.self, from: XCTUnwrap("1".data(using: .utf8))), .mousePointer)
        XCTAssertEqual(try decoder.decode(OverlayTrayLocation.self, from: XCTUnwrap("2".data(using: .utf8))), .controlIcon)
        XCTAssertEqual(try decoder.decode(OverlayTrayLocation.self, from: XCTUnwrap("3".data(using: .utf8))), .leftAligned)
        XCTAssertEqual(try decoder.decode(OverlayTrayLocation.self, from: XCTUnwrap("4".data(using: .utf8))), .rightAligned)
    }

    // MARK: - fromString() Tests

    func testFromStringDynamic() {
        XCTAssertEqual(OverlayTrayLocation.fromString("dynamic"), .dynamic)
    }

    func testFromStringMousePointer() {
        XCTAssertEqual(OverlayTrayLocation.fromString("mousePointer"), .mousePointer)
    }

    func testFromStringControlIcon() {
        XCTAssertEqual(OverlayTrayLocation.fromString("controlIcon"), .controlIcon)
    }

    func testFromStringLeftAligned() {
        XCTAssertEqual(OverlayTrayLocation.fromString("leftAligned"), .leftAligned)
    }

    func testFromStringRightAligned() {
        XCTAssertEqual(OverlayTrayLocation.fromString("rightAligned"), .rightAligned)
    }

    func testFromStringNumericZero() {
        XCTAssertEqual(OverlayTrayLocation.fromString("0"), .dynamic)
    }

    func testFromStringNumericOne() {
        XCTAssertEqual(OverlayTrayLocation.fromString("1"), .mousePointer)
    }

    func testFromStringNumericTwo() {
        XCTAssertEqual(OverlayTrayLocation.fromString("2"), .controlIcon)
    }

    func testFromStringNumericThree() {
        XCTAssertEqual(OverlayTrayLocation.fromString("3"), .leftAligned)
    }

    func testFromStringNumericFour() {
        XCTAssertEqual(OverlayTrayLocation.fromString("4"), .rightAligned)
    }

    func testFromStringInvalid() {
        XCTAssertNil(OverlayTrayLocation.fromString("invalid"))
        XCTAssertNil(OverlayTrayLocation.fromString("5"))
        XCTAssertNil(OverlayTrayLocation.fromString(""))
        XCTAssertNil(OverlayTrayLocation.fromString("Dynamic")) // case sensitive
        XCTAssertNil(OverlayTrayLocation.fromString("mouse_pointer")) // snake_case not supported
        XCTAssertNil(OverlayTrayLocation.fromString("continuum_icon"))
        XCTAssertNil(OverlayTrayLocation.fromString("left_aligned"))
        XCTAssertNil(OverlayTrayLocation.fromString("right_aligned"))
    }
}
