//
//  NewItemsPlacementTests.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Continuum
import XCTest

// MARK: - MenuBarNewItemsPlacement.Relation Tests

final class NewItemsPlacementRelationTests: XCTestCase {
    // MARK: - Raw Values

    func testLeftOfAnchorRawValue() {
        let relation = MenuBarNewItemsPlacement.Relation.leftOfAnchor
        XCTAssertEqual(relation.rawValue, "leftOfAnchor")
    }

    func testRightOfAnchorRawValue() {
        let relation = MenuBarNewItemsPlacement.Relation.rightOfAnchor
        XCTAssertEqual(relation.rawValue, "rightOfAnchor")
    }

    func testSectionDefaultRawValue() {
        let relation = MenuBarNewItemsPlacement.Relation.sectionDefault
        XCTAssertEqual(relation.rawValue, "sectionDefault")
    }

    // MARK: - Init from Raw Value

    func testInitFromLeftOfAnchorRawValue() {
        let relation = MenuBarNewItemsPlacement.Relation(rawValue: "leftOfAnchor")
        XCTAssertEqual(relation, .leftOfAnchor)
    }

    func testInitFromRightOfAnchorRawValue() {
        let relation = MenuBarNewItemsPlacement.Relation(rawValue: "rightOfAnchor")
        XCTAssertEqual(relation, .rightOfAnchor)
    }

    func testInitFromSectionDefaultRawValue() {
        let relation = MenuBarNewItemsPlacement.Relation(rawValue: "sectionDefault")
        XCTAssertEqual(relation, .sectionDefault)
    }

    func testInitFromInvalidRawValue() {
        let relation = MenuBarNewItemsPlacement.Relation(rawValue: "invalid")
        XCTAssertNil(relation)
    }

    // MARK: - Codable

    func testRelationEncode() throws {
        let relation = MenuBarNewItemsPlacement.Relation.leftOfAnchor
        let encoder = JSONEncoder()
        let data = try encoder.encode(relation)
        let json = String(data: data, encoding: .utf8)

        XCTAssertEqual(json, "\"leftOfAnchor\"")
    }

    func testRelationDecode() throws {
        let json = "\"rightOfAnchor\""
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()
        let relation = try decoder.decode(MenuBarNewItemsPlacement.Relation.self, from: data)

        XCTAssertEqual(relation, .rightOfAnchor)
    }

    func testRelationDecodeInvalid() throws {
        let json = "\"invalidValue\""
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()

        XCTAssertThrowsError(try decoder.decode(MenuBarNewItemsPlacement.Relation.self, from: data))
    }

    // MARK: - Equality

    func testRelationEquality() {
        XCTAssertEqual(
            MenuBarNewItemsPlacement.Relation.leftOfAnchor,
            MenuBarNewItemsPlacement.Relation.leftOfAnchor
        )
        XCTAssertNotEqual(
            MenuBarNewItemsPlacement.Relation.leftOfAnchor,
            MenuBarNewItemsPlacement.Relation.rightOfAnchor
        )
    }
}

// MARK: - MenuBarNewItemsPlacement Tests

final class NewItemsPlacementTests: XCTestCase {
    // MARK: - Initialization

    func testBasicInit() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        XCTAssertEqual(placement.sectionKey, "hidden")
        XCTAssertNil(placement.anchorIdentifier)
        XCTAssertEqual(placement.relation, .sectionDefault)
    }

    func testInitWithAnchor() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: "com.example.app:Item",
            relation: .leftOfAnchor
        )

        XCTAssertEqual(placement.sectionKey, "visible")
        XCTAssertEqual(placement.anchorIdentifier, "com.example.app:Item")
        XCTAssertEqual(placement.relation, .leftOfAnchor)
    }

    func testInitWithRightOfAnchor() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "alwaysHidden",
            anchorIdentifier: "com.other.app:OtherItem",
            relation: .rightOfAnchor
        )

        XCTAssertEqual(placement.sectionKey, "alwaysHidden")
        XCTAssertEqual(placement.anchorIdentifier, "com.other.app:OtherItem")
        XCTAssertEqual(placement.relation, .rightOfAnchor)
    }

    // MARK: - Default Value

    func testDefaultValueExists() {
        let defaultValue = MenuBarNewItemsPlacement.defaultValue

        XCTAssertNotNil(defaultValue)
        XCTAssertNil(defaultValue.anchorIdentifier)
        XCTAssertEqual(defaultValue.relation, .sectionDefault)
    }

    func testDefaultValueSectionKey() {
        let defaultValue = MenuBarNewItemsPlacement.defaultValue

        // Default section should be "hidden" per Defaults.DefaultValue.newItemsSection
        XCTAssertEqual(defaultValue.sectionKey, Defaults.DefaultValue.newItemsSection)
    }

    // MARK: - Equality

    func testEqualityIdentical() {
        let placement1 = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "com.app:Item",
            relation: .leftOfAnchor
        )
        let placement2 = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "com.app:Item",
            relation: .leftOfAnchor
        )

        XCTAssertEqual(placement1, placement2)
    }

    func testEqualityDifferentSection() {
        let placement1 = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
        let placement2 = MenuBarNewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        XCTAssertNotEqual(placement1, placement2)
    }

    func testEqualityDifferentAnchor() {
        let placement1 = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "anchor1",
            relation: .leftOfAnchor
        )
        let placement2 = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "anchor2",
            relation: .leftOfAnchor
        )

        XCTAssertNotEqual(placement1, placement2)
    }

    func testEqualityDifferentRelation() {
        let placement1 = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "anchor",
            relation: .leftOfAnchor
        )
        let placement2 = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "anchor",
            relation: .rightOfAnchor
        )

        XCTAssertNotEqual(placement1, placement2)
    }

    func testEqualityNilVsNonNilAnchor() {
        let placement1 = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
        let placement2 = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "com.app:Item",
            relation: .sectionDefault
        )

        XCTAssertNotEqual(placement1, placement2)
    }

    // MARK: - Codable

    func testEncodeBasic() throws {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(placement)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"sectionKey\":\"hidden\""))
        XCTAssertTrue(json.contains("\"relation\":\"sectionDefault\""))
    }

    func testEncodeWithAnchor() throws {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: "com.example.app:StatusItem",
            relation: .leftOfAnchor
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(placement)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"anchorIdentifier\":\"com.example.app:StatusItem\""))
        XCTAssertTrue(json.contains("\"relation\":\"leftOfAnchor\""))
    }

    func testDecodeBasic() throws {
        let json = """
        {
            "sectionKey": "hidden",
            "anchorIdentifier": null,
            "relation": "sectionDefault"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()

        let placement = try decoder.decode(MenuBarNewItemsPlacement.self, from: data)

        XCTAssertEqual(placement.sectionKey, "hidden")
        XCTAssertNil(placement.anchorIdentifier)
        XCTAssertEqual(placement.relation, .sectionDefault)
    }

    func testDecodeWithAnchor() throws {
        let json = """
        {
            "sectionKey": "alwaysHidden",
            "anchorIdentifier": "com.test.app:Item",
            "relation": "rightOfAnchor"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()

        let placement = try decoder.decode(MenuBarNewItemsPlacement.self, from: data)

        XCTAssertEqual(placement.sectionKey, "alwaysHidden")
        XCTAssertEqual(placement.anchorIdentifier, "com.test.app:Item")
        XCTAssertEqual(placement.relation, .rightOfAnchor)
    }

    func testDecodeInvalidRelation() throws {
        let json = """
        {
            "sectionKey": "hidden",
            "anchorIdentifier": null,
            "relation": "invalidRelation"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()

        XCTAssertThrowsError(try decoder.decode(MenuBarNewItemsPlacement.self, from: data))
    }

    func testDecodeMissingOptionalField() throws {
        let json = """
        {
            "sectionKey": "hidden",
            "relation": "sectionDefault"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()

        // anchorIdentifier is Optional<String>, so missing key decodes as nil
        let placement = try decoder.decode(MenuBarNewItemsPlacement.self, from: data)

        XCTAssertEqual(placement.sectionKey, "hidden")
        XCTAssertNil(placement.anchorIdentifier)
        XCTAssertEqual(placement.relation, .sectionDefault)
    }

    // MARK: - Round Trip

    func testRoundTripBasic() throws {
        let original = MenuBarNewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MenuBarNewItemsPlacement.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testRoundTripWithAnchor() throws {
        let original = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "com.complexapp.identifier:Very Long Item Name With Spaces",
            relation: .leftOfAnchor
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MenuBarNewItemsPlacement.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testRoundTripDefaultValue() throws {
        let original = MenuBarNewItemsPlacement.defaultValue

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MenuBarNewItemsPlacement.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - All Relations

    func testAllRelationsCovered() {
        // Ensure all three relations can be used in placements
        let leftPlacement = MenuBarNewItemsPlacement(
            sectionKey: "test",
            anchorIdentifier: "anchor",
            relation: .leftOfAnchor
        )
        let rightPlacement = MenuBarNewItemsPlacement(
            sectionKey: "test",
            anchorIdentifier: "anchor",
            relation: .rightOfAnchor
        )
        let defaultPlacement = MenuBarNewItemsPlacement(
            sectionKey: "test",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        XCTAssertEqual(leftPlacement.relation, .leftOfAnchor)
        XCTAssertEqual(rightPlacement.relation, .rightOfAnchor)
        XCTAssertEqual(defaultPlacement.relation, .sectionDefault)
    }
}

// MARK: - MenuBarNewItemsPlacementPreference Tests

final class MenuBarNewItemsPlacementPreferenceTests: XCTestCase {
    func testLoadPrefersEncodedPlacementOverLegacySection() throws {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "alwaysHidden",
            anchorIdentifier: "com.example.anchor:Item",
            relation: .rightOfAnchor
        )
        let data = try XCTUnwrap(MenuBarNewItemsPlacementPreference.encodedData(for: placement))

        let loaded = MenuBarNewItemsPlacementPreference.load(
            encodedData: data,
            legacySectionKey: "visible"
        )

        XCTAssertEqual(loaded, placement)
    }

    func testLoadMigratesLegacySectionWhenEncodedPlacementIsMissing() {
        let loaded = MenuBarNewItemsPlacementPreference.load(
            encodedData: nil,
            legacySectionKey: "visible"
        )

        XCTAssertEqual(loaded.sectionKey, "visible")
        XCTAssertNil(loaded.anchorIdentifier)
        XCTAssertEqual(loaded.relation, .sectionDefault)
    }

    func testLoadFallsBackToHiddenWhenEncodedPlacementIsInvalid() {
        let loaded = MenuBarNewItemsPlacementPreference.load(
            encodedData: Data("not-json".utf8),
            legacySectionKey: nil
        )

        XCTAssertEqual(loaded, MenuBarNewItemsPlacement.defaultValue)
    }

    func testLoadFallsBackToHiddenForUnknownLegacySection() {
        let loaded = MenuBarNewItemsPlacementPreference.load(
            encodedData: nil,
            legacySectionKey: "unknown"
        )

        XCTAssertEqual(loaded.sectionKey, "hidden")
        XCTAssertNil(loaded.anchorIdentifier)
        XCTAssertEqual(loaded.relation, .sectionDefault)
    }

    func testEncodedDataRoundTripsPlacement() throws {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "com.example.anchor:Item",
            relation: .leftOfAnchor
        )
        let data = try XCTUnwrap(MenuBarNewItemsPlacementPreference.encodedData(for: placement))

        let loaded = MenuBarNewItemsPlacementPreference.load(
            encodedData: data,
            legacySectionKey: nil
        )

        XCTAssertEqual(loaded, placement)
    }
}

// MARK: - MenuBarNewItemsPlacementPolicy Tests

final class MenuBarNewItemsPlacementPolicyTests: XCTestCase {
    func testEffectiveSectionClampsAlwaysHiddenWhenDisabled() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "alwaysHidden",
            anchorIdentifier: "com.example.anchor:Item",
            relation: .leftOfAnchor
        )

        XCTAssertEqual(
            MenuBarNewItemsPlacementPolicy.effectiveSection(
                placement: placement,
                alwaysHiddenEnabled: false
            ),
            .hidden
        )
        XCTAssertEqual(
            MenuBarNewItemsPlacementPolicy.effectiveSection(
                placement: placement,
                alwaysHiddenEnabled: true
            ),
            .alwaysHidden
        )
    }

    func testBadgeIndexUsesAnchorWhenPresent() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "com.example.anchor:Item",
            relation: .rightOfAnchor
        )

        let index = MenuBarNewItemsPlacementPolicy.badgeIndex(
            in: .hidden,
            itemIdentifiers: [
                "com.example.left:Item",
                "com.example.anchor:Item",
                "com.example.right:Item",
            ],
            placement: placement,
            savedSectionOrder: [:],
            alwaysHiddenEnabled: false
        )

        XCTAssertEqual(index, 2)
    }

    func testBadgeIndexUsesNearestSavedSiblingWhenAnchorIsMissing() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "com.example.anchor:Item",
            relation: .leftOfAnchor
        )
        let hiddenKey = MenuBarNewItemsPlacementPolicy.sectionKey(for: .hidden)

        let index = MenuBarNewItemsPlacementPolicy.badgeIndex(
            in: .hidden,
            itemIdentifiers: [
                "com.example.left:Item",
                "com.example.right:Item",
            ],
            placement: placement,
            savedSectionOrder: [
                hiddenKey: [
                    "com.example.left:Item",
                    "com.example.anchor:Item",
                    "com.example.right:Item",
                ],
            ],
            alwaysHiddenEnabled: false
        )

        XCTAssertEqual(index, 1)
    }

    func testUpdatedPlacementRecordsNearestNeighborFromDraggedBadge() {
        let placement = MenuBarNewItemsPlacementPolicy.updatedPlacement(
            for: .hidden,
            arrangedElements: [
                .item(identifier: "com.example.left:Item"),
                .newItemsBadge,
                .item(identifier: "com.example.right:Item"),
            ],
            alwaysHiddenEnabled: true
        )

        XCTAssertEqual(placement.sectionKey, "hidden")
        XCTAssertEqual(placement.anchorIdentifier, "com.example.right:Item")
        XCTAssertEqual(placement.relation, .leftOfAnchor)
    }

    func testUpdatedPlacementFallsBackToLeftNeighborAtSectionEnd() {
        let placement = MenuBarNewItemsPlacementPolicy.updatedPlacement(
            for: .visible,
            arrangedElements: [
                .item(identifier: "com.example.left:Item"),
                .newItemsBadge,
            ],
            alwaysHiddenEnabled: true
        )

        XCTAssertEqual(placement.sectionKey, "visible")
        XCTAssertEqual(placement.anchorIdentifier, "com.example.left:Item")
        XCTAssertEqual(placement.relation, .rightOfAnchor)
    }

    func testAppliedPlacementClampsAlwaysHiddenToHiddenAnchorWhenDisabled() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "alwaysHidden",
            anchorIdentifier: "com.example.stale:AlwaysHidden",
            relation: .rightOfAnchor
        )

        let adjusted = MenuBarNewItemsPlacementPolicy.appliedPlacement(
            placement,
            hiddenItems: [
                .init(
                    identifier: MenuBarItemTag.hiddenControlItem.tagIdentifier,
                    isControlItem: true,
                    instanceIndex: 0
                ),
                .init(
                    identifier: "com.example.hidden:Stable",
                    isControlItem: false,
                    instanceIndex: 0
                ),
            ],
            alwaysHiddenEnabled: false
        )

        XCTAssertEqual(adjusted.sectionKey, "hidden")
        XCTAssertEqual(adjusted.anchorIdentifier, "com.example.hidden:Stable")
        XCTAssertEqual(adjusted.relation, .leftOfAnchor)
    }

    func testAppliedPlacementDropsStaleAnchorWhenNoHiddenAnchorExists() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "alwaysHidden",
            anchorIdentifier: "com.example.stale:AlwaysHidden",
            relation: .rightOfAnchor
        )

        let adjusted = MenuBarNewItemsPlacementPolicy.appliedPlacement(
            placement,
            hiddenItems: [
                .init(
                    identifier: MenuBarItemTag.hiddenControlItem.tagIdentifier,
                    isControlItem: true,
                    instanceIndex: 0
                ),
            ],
            alwaysHiddenEnabled: false
        )

        XCTAssertEqual(adjusted.sectionKey, "hidden")
        XCTAssertNil(adjusted.anchorIdentifier)
        XCTAssertEqual(adjusted.relation, .sectionDefault)
    }

    func testMoveDestinationIntentUsesAnchorWhenPresent() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: "com.example.anchor:Item",
            relation: .leftOfAnchor
        )

        let intent = MenuBarNewItemsPlacementPolicy.moveDestinationIntent(
            placement: placement,
            liveSectionItemIdentifiers: [
                "com.example.left:Item",
                "com.example.anchor:Item",
            ],
            targetSection: .hidden,
            alwaysHiddenEnabled: false,
            hasAlwaysHiddenControl: false
        )

        XCTAssertEqual(intent, .leftOfIdentifier("com.example.anchor:Item"))
    }

    func testMoveDestinationIntentIgnoresAnchorFromDifferentSection() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: "com.example.anchor:Item",
            relation: .rightOfAnchor
        )

        let intent = MenuBarNewItemsPlacementPolicy.moveDestinationIntent(
            placement: placement,
            liveSectionItemIdentifiers: [
                "com.example.anchor:Item",
            ],
            targetSection: .hidden,
            alwaysHiddenEnabled: false,
            hasAlwaysHiddenControl: false
        )

        XCTAssertEqual(intent, .leftOfControl(.hidden))
    }

    func testMoveDestinationIntentUsesHiddenBoundaryWhenAlwaysHiddenControlIsAvailable() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        let intent = MenuBarNewItemsPlacementPolicy.moveDestinationIntent(
            placement: placement,
            liveSectionItemIdentifiers: [],
            targetSection: .hidden,
            alwaysHiddenEnabled: true,
            hasAlwaysHiddenControl: true
        )

        XCTAssertEqual(intent, .rightOfControl(.alwaysHidden))
    }

    func testMoveDestinationIntentFallsBackWhenAlwaysHiddenControlIsMissing() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "alwaysHidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        let intent = MenuBarNewItemsPlacementPolicy.moveDestinationIntent(
            placement: placement,
            liveSectionItemIdentifiers: [],
            targetSection: .alwaysHidden,
            alwaysHiddenEnabled: true,
            hasAlwaysHiddenControl: false
        )

        XCTAssertEqual(intent, .leftOfControl(.hidden))
    }
}
