//
//  PlanPendingMoveTests.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Continuum
import XCTest

/// Characterization tests for PendingLedger.planPendingMove.
///
/// Pins down the per-entry decision logic used by relocatePendingItems:
/// actively-shown short-circuit, waitForRelaunch sentinel handling,
/// item-already-hidden cleanup, destination resolution (stored neighbor →
/// fallback neighbor → section boundary), and itemNotPresent skipping.
///
/// Coordinate convention: hidden divider at x=400, width=10. Items in
/// "visible" sit at x >= 410. Items in "hidden" sit at x < 400.
final class PlanPendingMoveTests: XCTestCase {
    // MARK: - Helpers

    private let hiddenBounds = CGRect(x: 400, y: 0, width: 10, height: 22)

    private func appTag(_ bundleID: String, _ title: String, _ instanceIndex: Int = 0) -> MenuBarItemTag {
        .appItem(bundleID: bundleID, title: title, instanceIndex: instanceIndex)
    }

    private func visibleItem(
        bundleID: String,
        title: String,
        windowID: CGWindowID,
        x: CGFloat = 500
    ) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: appTag(bundleID, title),
            windowID: windowID,
            bounds: CGRect(x: x, y: 0, width: 24, height: 22)
        )
    }

    private func hiddenItem(
        bundleID: String,
        title: String,
        windowID: CGWindowID,
        x: CGFloat = 200
    ) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: appTag(bundleID, title),
            windowID: windowID,
            bounds: CGRect(x: x, y: 0, width: 24, height: 22)
        )
    }

    private func pair() -> MenuBarControlItems {
        MenuBarControlItems.fixture(
            hiddenAt: hiddenBounds,
            alwaysHiddenAt: CGRect(x: 100, y: 0, width: 10, height: 22)
        )
    }

    // MARK: - Scenarios

    func testWaitForRelaunchValueRoundTripsThroughLedgerParser() {
        let value = PendingLedger.makeWaitForRelaunchValue(
            windowID: 12345,
            section: .alwaysHidden
        )
        let parsed = PendingLedger.parseWaitForRelaunchValue(value)

        XCTAssertEqual(value, "waitForRelaunch:12345:alwaysHidden")
        XCTAssertEqual(parsed?.windowID, 12345)
        XCTAssertEqual(parsed?.section, .alwaysHidden)
    }

    func testWaitForRelaunchParserRejectsPlainAndMalformedValues() {
        XCTAssertNil(PendingLedger.parseWaitForRelaunchValue("hidden"))
        XCTAssertNil(PendingLedger.parseWaitForRelaunchValue("waitForRelaunch:12345"))
        XCTAssertNil(PendingLedger.parseWaitForRelaunchValue("waitForRelaunch:not-a-window:hidden"))
        XCTAssertNil(PendingLedger.parseWaitForRelaunchValue("waitForRelaunch:12345:notASection"))
    }

    func testPendingEntryParserAcceptsSectionsAndSentinels() {
        let sectionEntry = PendingLedger.parsePendingEntry(
            tagIdentifier: "com.example.app:Status",
            rawValue: PendingLedger.sectionKey(for: .hidden)
        )
        XCTAssertEqual(
            sectionEntry,
            PendingLedger.PendingEntry(
                tagIdentifier: "com.example.app:Status",
                kind: .section(.hidden)
            )
        )
        XCTAssertEqual(sectionEntry?.targetSection, .hidden)

        let sentinelEntry = PendingLedger.parsePendingEntry(
            tagIdentifier: "com.example.app:Status",
            rawValue: PendingLedger.makeWaitForRelaunchValue(
                windowID: 12345,
                section: .alwaysHidden
            )
        )
        XCTAssertEqual(
            sentinelEntry,
            PendingLedger.PendingEntry(
                tagIdentifier: "com.example.app:Status",
                kind: .waitForRelaunch(windowID: 12345, section: .alwaysHidden)
            )
        )
        XCTAssertEqual(sentinelEntry?.targetSection, .alwaysHidden)
    }

    func testPendingEntryParserRejectsMalformedValues() {
        XCTAssertNil(
            PendingLedger.parsePendingEntry(
                tagIdentifier: "com.example.app:Status",
                rawValue: "notASection"
            )
        )
        XCTAssertNil(
            PendingLedger.parsePendingEntry(
                tagIdentifier: "com.example.app:Status",
                rawValue: "waitForRelaunch:not-a-window:hidden"
            )
        )
    }

    func testPendingReturnDestinationRoundTripsThroughStorage() {
        let neighbor = visibleItem(bundleID: "com.example.app", title: "Neighbor", windowID: 799)
        let destination = PendingLedger.makePendingReturnDestination(for: .rightOfItem(neighbor))

        XCTAssertEqual(
            destination,
            PendingLedger.PendingReturnDestination(
                neighborTagIdentifier: neighbor.tag.tagIdentifier,
                position: .right
            )
        )
        XCTAssertEqual(
            destination.storageValue,
            [
                "neighbor": neighbor.tag.tagIdentifier,
                "position": "right",
            ]
        )
        XCTAssertEqual(
            PendingLedger.PendingReturnDestination(storageValue: destination.storageValue),
            destination
        )
        XCTAssertNil(
            PendingLedger.PendingReturnDestination(
                storageValue: [
                    "neighbor": neighbor.tag.tagIdentifier,
                    "position": "sideways",
                ]
            )
        )
    }

    func testRelocationPlanningInputBuildsActiveTagsAndFallbackNeighbors() {
        let shown = visibleItem(bundleID: "com.example.shown", title: "Shown", windowID: 790)
        let stuck = visibleItem(bundleID: "com.example.stuck", title: "Stuck", windowID: 791)
        let fallback = visibleItem(bundleID: "com.example.fallback", title: "Fallback", windowID: 792)
        let storedDestination = PendingLedger.makePendingReturnDestination(for: .leftOfItem(fallback))

        let input = PendingLedger.relocationPlanningInput(
            contexts: [
                PendingLedger.RehideContextObservation(
                    tag: shown.tag,
                    fallbackNeighbor: nil
                ),
                PendingLedger.RehideContextObservation(
                    tag: stuck.tag,
                    fallbackNeighbor: fallback.tag
                ),
            ],
            pendingReturnDestinations: [
                stuck.tag.tagIdentifier: storedDestination.storageValue,
            ]
        )

        XCTAssertEqual(input.activelyShownTags, [
            shown.tag.tagIdentifier,
            stuck.tag.tagIdentifier,
        ])
        XCTAssertEqual(
            input.returnInfo.destinations[stuck.tag.tagIdentifier],
            storedDestination.storageValue
        )
        XCTAssertEqual(
            input.returnInfo.fallbackNeighbors,
            [
                stuck.tag.tagIdentifier: fallback.tag,
            ]
        )
    }

    func testPendingRelocationLedgerRecordsAndClearsPairedState() {
        let item = visibleItem(bundleID: "com.example.item", title: "Item", windowID: 785)
        let neighbor = visibleItem(bundleID: "com.example.neighbor", title: "Neighbor", windowID: 786)
        let metadata = MenuBarTemporaryRevealPolicy.pendingMetadata(
            originalSection: .hidden,
            returnDestination: .leftOfItem(neighbor)
        )
        var ledger = PendingRelocationLedger()

        ledger.record(metadata, for: item.tag.tagIdentifier)

        XCTAssertEqual(
            ledger.relocations[item.tag.tagIdentifier],
            PendingLedger.sectionKey(for: .hidden)
        )
        XCTAssertEqual(
            ledger.returnDestinations[item.tag.tagIdentifier],
            metadata.returnDestinationStorageValue
        )
        XCTAssertEqual(
            ledger.pendingEntry(for: item.tag.tagIdentifier),
            PendingLedger.PendingEntry(
                tagIdentifier: item.tag.tagIdentifier,
                kind: .section(.hidden)
            )
        )
        XCTAssertTrue(ledger.clear(tagIdentifier: item.tag.tagIdentifier))
        XCTAssertTrue(ledger.isEmpty)
        XCTAssertNil(ledger.returnDestinations[item.tag.tagIdentifier])
    }

    func testPendingRelocationLedgerMarksWaitForRelaunchWithoutDroppingDestination() {
        let item = visibleItem(bundleID: "com.example.item", title: "Item", windowID: 787)
        let neighbor = visibleItem(bundleID: "com.example.neighbor", title: "Neighbor", windowID: 788)
        let metadata = MenuBarTemporaryRevealPolicy.pendingMetadata(
            originalSection: .hidden,
            returnDestination: .rightOfItem(neighbor)
        )
        let waitValue = PendingLedger.makeWaitForRelaunchValue(
            windowID: item.windowID,
            section: .hidden
        )
        var ledger = PendingRelocationLedger()

        ledger.record(metadata, for: item.tag.tagIdentifier)
        ledger.markWaitForRelaunch(waitValue, for: item.tag.tagIdentifier)

        XCTAssertEqual(ledger.relocations[item.tag.tagIdentifier], waitValue)
        XCTAssertEqual(
            ledger.returnDestinations[item.tag.tagIdentifier],
            metadata.returnDestinationStorageValue
        )
        XCTAssertEqual(
            ledger.pendingEntry(for: item.tag.tagIdentifier),
            PendingLedger.PendingEntry(
                tagIdentifier: item.tag.tagIdentifier,
                kind: .waitForRelaunch(windowID: item.windowID, section: .hidden)
            )
        )
    }

    func testPendingRelocationLedgerPromotesWaitForRelaunchToSectionEntry() {
        let tagIdentifier = "com.example.item:Item"
        var ledger = PendingRelocationLedger()

        ledger.load(
            relocations: [
                tagIdentifier: PendingLedger.makeWaitForRelaunchValue(
                    windowID: 789,
                    section: .alwaysHidden
                ),
            ],
            returnDestinations: [:]
        )

        ledger.promoteWaitForRelaunch(for: tagIdentifier, to: .alwaysHidden)

        XCTAssertEqual(
            ledger.relocations[tagIdentifier],
            PendingLedger.sectionKey(for: .alwaysHidden)
        )
        XCTAssertEqual(
            ledger.pendingEntry(for: tagIdentifier),
            PendingLedger.PendingEntry(
                tagIdentifier: tagIdentifier,
                kind: .section(.alwaysHidden)
            )
        )
    }

    func testPendingRelocationLedgerBuildsPlanningInputFromStoredDestinations() {
        let shown = visibleItem(bundleID: "com.example.shown", title: "Shown", windowID: 781)
        let stuck = visibleItem(bundleID: "com.example.stuck", title: "Stuck", windowID: 782)
        let fallback = visibleItem(bundleID: "com.example.fallback", title: "Fallback", windowID: 783)
        let storedDestination = PendingLedger.makePendingReturnDestination(for: .leftOfItem(fallback))
        var ledger = PendingRelocationLedger()

        ledger.load(
            relocations: [
                stuck.tag.tagIdentifier: PendingLedger.sectionKey(for: .hidden),
            ],
            returnDestinations: [
                stuck.tag.tagIdentifier: storedDestination.storageValue,
            ]
        )

        let input = ledger.relocationPlanningInput(
            contexts: [
                PendingLedger.RehideContextObservation(
                    tag: shown.tag,
                    fallbackNeighbor: nil
                ),
                PendingLedger.RehideContextObservation(
                    tag: stuck.tag,
                    fallbackNeighbor: fallback.tag
                ),
            ]
        )

        XCTAssertEqual(input.activelyShownTags, [
            shown.tag.tagIdentifier,
            stuck.tag.tagIdentifier,
        ])
        XCTAssertEqual(
            input.returnInfo.destinations[stuck.tag.tagIdentifier],
            storedDestination.storageValue
        )
        XCTAssertEqual(
            input.returnInfo.fallbackNeighbors[stuck.tag.tagIdentifier],
            fallback.tag
        )
    }

    func testBoundsByWindowIDIndexesLiveBoundsPerWindow() {
        let first = visibleItem(
            bundleID: "com.example.shared",
            title: "Shared",
            windowID: 793,
            x: 500
        )
        let second = MenuBarItem.fixture(
            tag: first.tag,
            windowID: 794,
            bounds: CGRect(x: 550, y: 0, width: 24, height: 22)
        )

        let bounds = PendingLedger.boundsByWindowID(items: [first, second]) { item in
            CGRect(x: item.bounds.minX + 10, y: item.bounds.minY, width: item.bounds.width, height: item.bounds.height)
        }

        XCTAssertEqual(bounds[first.windowID]?.minX, 510)
        XCTAssertEqual(bounds[second.windowID]?.minX, 560)
    }

    func testNotFoundRetryPolicyKeepsNineAttemptsInMemoryThenFallsBackToPendingRelocation() {
        XCTAssertEqual(PendingLedger.notFoundDecision(after: 1), .retryLater)
        XCTAssertEqual(PendingLedger.notFoundDecision(after: 9), .retryLater)
        XCTAssertEqual(PendingLedger.notFoundDecision(after: 10), .giveUpToPendingRelocation)
    }

    func testRehideFailurePolicyMovesFromImmediateRetryToTimerRetryToWaitForRelaunch() {
        XCTAssertEqual(PendingLedger.rehideFailureDecision(after: 1), .retryImmediately)
        XCTAssertEqual(PendingLedger.rehideFailureDecision(after: 2), .retryImmediately)
        XCTAssertEqual(PendingLedger.rehideFailureDecision(after: 3), .retryLater)
        XCTAssertEqual(PendingLedger.rehideFailureDecision(after: 8), .retryLater)
        XCTAssertEqual(PendingLedger.rehideFailureDecision(after: 9), .waitForRelaunch)
    }

    /// A standard pending entry for a visible item produces a move to the
    /// section boundary (no stored neighbor, no fallback).
    func testStandardEntryVisibleItemFallsBackToSectionBoundary() {
        let item = visibleItem(bundleID: "com.example.app", title: "Status", windowID: 800)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .section(.hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        if case let .move(movedItem, destination) = decision {
            XCTAssertEqual(movedItem.windowID, 800)
            if case let .leftOfItem(neighbor) = destination {
                XCTAssertEqual(
                    neighbor.tag,
                    .hiddenControlItem,
                    "section-boundary fallback should target the hidden control item"
                )
            } else {
                XCTFail("expected .leftOfItem, got \(destination)")
            }
        } else {
            XCTFail("expected .move, got \(decision)")
        }
    }

    /// A pending entry whose item is already in the hidden section
    /// produces .clearEntry — no move needed.
    func testStandardEntryAlreadyHiddenClearsEntry() {
        let item = hiddenItem(bundleID: "com.example.app", title: "Status", windowID: 801)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .section(.hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        if case .clearEntry = decision {
            // expected
        } else {
            XCTFail("expected .clearEntry, got \(decision)")
        }
    }

    /// When the item referenced by the pending entry is not in the current
    /// items list, the planner emits .skip(.itemNotPresent) — the entry
    /// stays in the dict for the next launch.
    func testItemNotPresentSkips() {
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: "com.gone.app:Status",
            kind: .section(.hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        XCTAssertEqual(decision, .skip(reason: .itemNotPresent))
    }

    /// waitForRelaunch sentinel with the same windowID skips with
    /// .waitForRelaunchActive.
    func testWaitForRelaunchSameWindowIDSkips() {
        let item = visibleItem(bundleID: "com.example.app", title: "Status", windowID: 802)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .waitForRelaunch(windowID: 802, section: .hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        XCTAssertEqual(decision, .skip(reason: .waitForRelaunchActive))
    }

    /// waitForRelaunch sentinel with a new windowID (app relaunched)
    /// promotes the entry. The orchestrator persists the change and
    /// re-runs the planner.
    func testWaitForRelaunchNewWindowIDPromotes() {
        let item = visibleItem(bundleID: "com.example.app", title: "Status", windowID: 803)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .waitForRelaunch(windowID: 999, section: .hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        if case let .promoteWaitForRelaunch(section) = decision {
            XCTAssertEqual(section, .hidden)
        } else {
            XCTFail("expected .promoteWaitForRelaunch, got \(decision)")
        }
    }

    /// An entry whose tag is currently in activelyShownTags skips with
    /// .activelyShown — the rehide flow owns this item.
    func testActivelyShownExclusion() {
        let item = visibleItem(bundleID: "com.example.app", title: "Status", windowID: 804)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .section(.hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [item.tag.tagIdentifier],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        XCTAssertEqual(decision, .skip(reason: .activelyShown))
    }

    /// An entry whose recorded section is .visible produces .clearEntry —
    /// there's no hidden destination to restore to.
    func testVisibleSectionShortCircuitsToClear() {
        let item = visibleItem(bundleID: "com.example.app", title: "Status", windowID: 805)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .section(.visible)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )

        if case .clearEntry = decision {
            // expected
        } else {
            XCTFail("expected .clearEntry, got \(decision)")
        }
    }

    /// A stored neighbor destination takes precedence over the fallback
    /// neighbor and the section boundary.
    func testStoredNeighborTakesPrecedence() {
        let item = visibleItem(bundleID: "com.example.app", title: "Status", windowID: 806, x: 500)
        let neighbor = visibleItem(bundleID: "com.example.app", title: "Other", windowID: 807, x: 600)
        let storedDestination = PendingLedger.makePendingReturnDestination(for: .leftOfItem(neighbor))
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .section(.hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item, neighbor],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [
                    item.tag.tagIdentifier: storedDestination.storageValue,
                ],
                fallbackNeighbors: [:]
            )
        )

        if case let .move(_, destination) = decision,
           case let .leftOfItem(target) = destination
        {
            XCTAssertEqual(
                target.windowID,
                807,
                "stored neighbor should win over the section-boundary fallback"
            )
        } else {
            XCTFail("expected .move(.leftOfItem(neighbor)), got \(decision)")
        }
    }

    func testMalformedStoredNeighborFallsBackInsteadOfGuessingSide() {
        let item = visibleItem(bundleID: "com.example.app", title: "Status", windowID: 808, x: 500)
        let neighbor = visibleItem(bundleID: "com.example.app", title: "Other", windowID: 809, x: 600)
        let entry = PendingLedger.PendingEntry(
            tagIdentifier: item.tag.tagIdentifier,
            kind: .section(.hidden)
        )

        let decision = PendingLedger.planPendingMove(
            entry: entry,
            items: [item, neighbor],
            controlItems: pair(),
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [:],
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [
                    item.tag.tagIdentifier: [
                        "neighbor": neighbor.tag.tagIdentifier,
                        "position": "sideways",
                    ],
                ],
                fallbackNeighbors: [:]
            )
        )

        if case let .move(_, destination) = decision,
           case let .leftOfItem(target) = destination
        {
            XCTAssertEqual(
                target.tag,
                .hiddenControlItem,
                "malformed stored destinations should fall back to the section boundary"
            )
        } else {
            XCTFail("expected section-boundary fallback, got \(decision)")
        }
    }
}
