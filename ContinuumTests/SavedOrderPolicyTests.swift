//
//  SavedOrderPolicyTests.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Continuum
import XCTest

final class SavedOrderPolicyTests: XCTestCase {
    func testBuildIncludesStableItemsAndVisibleControlOnly() {
        let visibleControl = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 100,
            sourcePID: nil
        )
        let stableItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.stable", title: "Stable"),
            windowID: 101,
            sourcePID: 2001
        )
        let titleOnlyItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.pending", title: "Pending"),
            windowID: 102,
            sourcePID: nil
        )
        let transientControlCenterItem = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "Item-7"),
            windowID: 103,
            sourcePID: 2003
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 104,
            sourcePID: nil
        )
        var cache = MenuBarItemCache(displayID: 1)
        cache[.visible] = [
            visibleControl,
            stableItem,
            titleOnlyItem,
            transientControlCenterItem,
        ]
        cache[.hidden] = [hiddenControl]

        let order = MenuBarSavedOrderPolicy.build(
            from: cache,
            previousSavedSectionOrder: [:],
            pendingReturnDestinations: [:],
            pendingRelocations: [:]
        )

        XCTAssertEqual(
            order[MenuBarSavedOrderPolicy.sectionKey(for: .visible)],
            [
                visibleControl.uniqueIdentifier,
                stableItem.uniqueIdentifier,
            ]
        )
        XCTAssertNil(order[MenuBarSavedOrderPolicy.sectionKey(for: .hidden)])
    }

    func testBuildMasksPendingRehideItemAndPreservesItsClosedAppSlot() {
        let temporarilyShownItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.hidden", title: "Hidden"),
            windowID: 110,
            sourcePID: 2010
        )
        let visibleNeighbor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.visible", title: "Visible"),
            windowID: 111,
            sourcePID: 2011
        )
        var cache = MenuBarItemCache(displayID: 1)
        cache[.visible] = [temporarilyShownItem, visibleNeighbor]

        let order = MenuBarSavedOrderPolicy.build(
            from: cache,
            previousSavedSectionOrder: [
                MenuBarSavedOrderPolicy.sectionKey(for: .hidden): [
                    temporarilyShownItem.uniqueIdentifier,
                ],
                MenuBarSavedOrderPolicy.sectionKey(for: .visible): [
                    visibleNeighbor.uniqueIdentifier,
                ],
            ],
            pendingReturnDestinations: [
                temporarilyShownItem.tag.tagIdentifier: [
                    "neighbor": visibleNeighbor.tag.tagIdentifier,
                    "position": "left",
                ],
            ],
            pendingRelocations: [:]
        )

        XCTAssertEqual(
            order[MenuBarSavedOrderPolicy.sectionKey(for: .hidden)],
            [temporarilyShownItem.uniqueIdentifier]
        )
        XCTAssertEqual(
            order[MenuBarSavedOrderPolicy.sectionKey(for: .visible)],
            [visibleNeighbor.uniqueIdentifier]
        )
    }

    func testBuildTreatsWaitForRelaunchSentinelAsPendingRehide() {
        let stuckItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.stuck", title: "Stuck"),
            windowID: 120,
            sourcePID: 2020
        )
        var cache = MenuBarItemCache(displayID: 1)
        cache[.visible] = [stuckItem]

        let order = MenuBarSavedOrderPolicy.build(
            from: cache,
            previousSavedSectionOrder: [
                MenuBarSavedOrderPolicy.sectionKey(for: .alwaysHidden): [
                    stuckItem.uniqueIdentifier,
                ],
            ],
            pendingReturnDestinations: [:],
            pendingRelocations: [
                stuckItem.tag.tagIdentifier: PendingLedger.makeWaitForRelaunchValue(
                    windowID: stuckItem.windowID,
                    section: .alwaysHidden
                ),
            ]
        )

        XCTAssertEqual(
            order[MenuBarSavedOrderPolicy.sectionKey(for: .alwaysHidden)],
            [stuckItem.uniqueIdentifier]
        )
        XCTAssertNil(order[MenuBarSavedOrderPolicy.sectionKey(for: .visible)])
    }

    func testBuildDropsPrunableSavedIdentifiers() {
        let stableItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.stable", title: "Stable"),
            windowID: 130,
            sourcePID: 2030
        )
        var cache = MenuBarItemCache(displayID: 1)
        cache[.visible] = [stableItem]

        let structuralIdentifier = "\(Constants.bundleIdentifier):Continuum.ControlItem.Visible"
        let genericControlCenterIdentifier = "com.apple.controlcenter:Item-7"
        let emptyControlCenterIdentifier = "com.apple.controlcenter:"
        let order = MenuBarSavedOrderPolicy.build(
            from: cache,
            previousSavedSectionOrder: [
                MenuBarSavedOrderPolicy.sectionKey(for: .visible): [
                    structuralIdentifier,
                    MenuBarItemTag.hiddenControlItem.tagIdentifier,
                    genericControlCenterIdentifier,
                    emptyControlCenterIdentifier,
                    stableItem.uniqueIdentifier,
                ],
            ],
            pendingReturnDestinations: [:],
            pendingRelocations: [:]
        )

        XCTAssertEqual(
            order[MenuBarSavedOrderPolicy.sectionKey(for: .visible)],
            [stableItem.uniqueIdentifier]
        )
    }

    func testPrunedSavedSectionOrderDropsStructuralAndGenericControlCenterIdentifiers() {
        let validIdentifier = "com.example.valid:Valid"
        let secondValidIdentifier = "com.example.second:Second"
        let visibleKey = MenuBarSavedOrderPolicy.sectionKey(for: .visible)
        let hiddenKey = MenuBarSavedOrderPolicy.sectionKey(for: .hidden)
        let structuralIdentifier = "\(Constants.bundleIdentifier):Continuum.ControlItem.Hidden"

        let order = MenuBarSavedOrderPolicy.prunedSavedSectionOrder([
            visibleKey: [
                validIdentifier,
                structuralIdentifier,
                MenuBarItemTag.alwaysHiddenControlItem.tagIdentifier,
                "com.apple.controlcenter:Item-0",
                "com.apple.controlcenter:",
            ],
            hiddenKey: [
                secondValidIdentifier,
            ],
        ])

        XCTAssertEqual(order[visibleKey], [validIdentifier])
        XCTAssertEqual(order[hiddenKey], [secondValidIdentifier])
    }

    func testSanitizedLayoutEditorOrderDropsUnstableAndEmptyIdentifiers() {
        let validIdentifier = "com.example.valid:Valid"
        let hiddenIdentifier = "com.example.hidden:Hidden"
        let visibleKey = MenuBarSavedOrderPolicy.sectionKey(for: .visible)
        let hiddenKey = MenuBarSavedOrderPolicy.sectionKey(for: .hidden)
        let structuralIdentifier = "\(Constants.bundleIdentifier):Continuum.ControlItem.Visible"

        let order = MenuBarSavedOrderPolicy.sanitizedLayoutEditorOrder([
            .visible: [
                "",
                validIdentifier,
                MenuBarItemTag.hiddenControlItem.tagIdentifier,
                structuralIdentifier,
                "com.apple.controlcenter:Item-3",
            ],
            .hidden: [
                hiddenIdentifier,
            ],
        ])

        XCTAssertEqual(order[visibleKey], [validIdentifier])
        XCTAssertEqual(order[hiddenKey], [hiddenIdentifier])
    }

    func testSavedSectionOrderLedgerLoadsReplacesAndClearsOrder() {
        let visibleKey = MenuBarSavedOrderPolicy.sectionKey(for: .visible)
        var ledger = MenuBarSavedSectionOrderLedger()

        ledger.load([visibleKey: ["com.example.first:First"]])

        XCTAssertFalse(ledger.isEmpty)
        XCTAssertEqual(ledger.entryCounts, [1])
        XCTAssertEqual(ledger.persistenceSnapshot, [visibleKey: ["com.example.first:First"]])

        ledger.replace(with: [visibleKey: ["com.example.second:Second"]])

        XCTAssertEqual(ledger.order, [visibleKey: ["com.example.second:Second"]])

        ledger.clear()

        XCTAssertTrue(ledger.isEmpty)
        XCTAssertEqual(ledger.persistenceSnapshot, [:])
    }

    func testSavedSectionOrderLedgerReportsChangedReplacements() {
        let visibleKey = MenuBarSavedOrderPolicy.sectionKey(for: .visible)
        var ledger = MenuBarSavedSectionOrderLedger()
        let order = [visibleKey: ["com.example.first:First"]]

        XCTAssertTrue(ledger.replaceIfChanged(with: order))
        XCTAssertFalse(ledger.replaceIfChanged(with: order))
        XCTAssertEqual(ledger.order, order)
    }
}
