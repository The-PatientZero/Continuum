//
//  ShouldPersistSavedOrderTests.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Continuum
import CoreGraphics
import XCTest

/// Characterization tests for MenuBarCacheCommitPolicy, the pure gate consumed
/// by uncheckedCacheItems to decide whether to write savedSectionOrder for the
/// current cache snapshot.
///
/// Pins down which in-flight orchestrator signals block a save. A
/// regression where any of these flags is dropped from the gate is
/// caught by the corresponding test below.
final class ShouldPersistSavedOrderTests: XCTestCase {
    /// All clear: every gate flag is false and no temporary contexts.
    /// The expected state for ordinary cache cycles between user
    /// actions.
    func testChangedCacheWithClearRuntimePersists() {
        XCTAssertEqual(MenuBarCacheCommitPolicy.savedOrderPersistenceDecision(
            cacheDidChange: true,
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: false,
            temporarilyShownItemContextsIsEmpty: true,
            hasBlockedItems: false
        ), .persist)
    }

    /// No cache change: the manager should record diagnostics but not rewrite
    /// savedSectionOrder.
    func testUnchangedCacheSkipsPersistence() {
        XCTAssertEqual(MenuBarCacheCommitPolicy.cacheUpdateAction(cacheDidChange: false), .recordSnapshotOnly)
        XCTAssertEqual(MenuBarCacheCommitPolicy.savedOrderPersistenceDecision(
            cacheDidChange: false,
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: false,
            temporarilyShownItemContextsIsEmpty: true,
            hasBlockedItems: false
        ), .skip(.cacheUnchanged))
    }

    /// Restore in flight: the cross-section / within-section restore
    /// loop is currently moving items; intermediate cache states must
    /// not be persisted.
    func testRestoringItemOrderBlocks() {
        XCTAssertEqual(MenuBarCacheCommitPolicy.savedOrderPersistenceDecision(
            cacheDidChange: true,
            isRestoringItemOrder: true,
            isResettingLayout: false,
            isInStartupSettling: false,
            temporarilyShownItemContextsIsEmpty: true,
            hasBlockedItems: false
        ), .skip(.restoringItemOrder))
    }

    /// Layout reset in flight (the user-triggered "Reset Layout" pass);
    /// transient mid-reset state is not the user's intent.
    func testResettingLayoutBlocks() {
        XCTAssertEqual(MenuBarCacheCommitPolicy.savedOrderPersistenceDecision(
            cacheDidChange: true,
            isRestoringItemOrder: false,
            isResettingLayout: true,
            isInStartupSettling: false,
            temporarilyShownItemContextsIsEmpty: true,
            hasBlockedItems: false
        ), .skip(.resettingLayout))
    }

    /// Cold-boot settling window: many apps register their NSStatusItems
    /// in quick succession; capturing a snapshot mid-settling can
    /// persist sourcePID-unresolved placeholder identifiers.
    func testInStartupSettlingBlocks() {
        XCTAssertEqual(MenuBarCacheCommitPolicy.savedOrderPersistenceDecision(
            cacheDidChange: true,
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: true,
            temporarilyShownItemContextsIsEmpty: true,
            hasBlockedItems: false
        ), .skip(.startupSettling))
    }

    /// Any temporarily-shown item is in flight: uncheckedCacheItems
    /// will route the item's cache entry to its return destination
    /// instead of its live visible position, so the save must wait
    /// until the rehide completes (or fails into pendingRelocations
    /// where the separate pendingRehideTagIdentifiers filter takes
    /// over).
    func testTemporarilyShownContextsNonEmptyBlocks() {
        XCTAssertEqual(MenuBarCacheCommitPolicy.savedOrderPersistenceDecision(
            cacheDidChange: true,
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: false,
            temporarilyShownItemContextsIsEmpty: false,
            hasBlockedItems: false
        ), .skip(.temporarilyShownItemsInFlight))
    }

    /// Blocked x=-1 windows are WindowServer transients. Persisting them would
    /// capture a moment where macOS has temporarily hidden the item rather than
    /// the user's intended order.
    func testBlockedItemsBlockPersistence() {
        var cache = MenuBarItemCache(displayID: 1)
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 10,
            bounds: CGRect(x: -1, y: 0, width: 24, height: 22)
        )
        cache[.hidden] = [item]

        XCTAssertTrue(MenuBarCacheCommitPolicy.containsBlockedItems(in: cache) { item in
            item.bounds
        })
        XCTAssertEqual(MenuBarCacheCommitPolicy.savedOrderPersistenceDecision(
            cacheDidChange: true,
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: false,
            temporarilyShownItemContextsIsEmpty: true,
            hasBlockedItems: true
        ), .skip(.blockedItems))
    }

    /// A restore flag that leaks past the operation timeout should not suppress
    /// future user-driven order saves forever.
    func testStaleRestoringFlagClearsAfterTimeout() {
        let startedAt = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(MenuBarCacheCommitPolicy.restorationFlagAction(
            isRestoringItemOrder: true,
            startedAt: startedAt,
            now: Date(timeIntervalSince1970: 109)
        ), .keep)
        XCTAssertEqual(MenuBarCacheCommitPolicy.restorationFlagAction(
            isRestoringItemOrder: true,
            startedAt: startedAt,
            now: Date(timeIntervalSince1970: 111)
        ), .clearStale)
        XCTAssertEqual(MenuBarCacheCommitPolicy.restorationFlagAction(
            isRestoringItemOrder: false,
            startedAt: startedAt,
            now: Date(timeIntervalSince1970: 111)
        ), .keep)
    }

    /// Two flags simultaneously: any blocking flag is sufficient to
    /// block the save. Sanity-check that the gate is the AND of all
    /// per-flag predicates rather than counting.
    func testMultipleBlockingFlagsAllBlock() {
        XCTAssertEqual(MenuBarCacheCommitPolicy.savedOrderPersistenceDecision(
            cacheDidChange: true,
            isRestoringItemOrder: true,
            isResettingLayout: true,
            isInStartupSettling: false,
            temporarilyShownItemContextsIsEmpty: true,
            hasBlockedItems: false
        ), .skip(.restoringItemOrder))
        XCTAssertEqual(MenuBarCacheCommitPolicy.savedOrderPersistenceDecision(
            cacheDidChange: true,
            isRestoringItemOrder: false,
            isResettingLayout: false,
            isInStartupSettling: true,
            temporarilyShownItemContextsIsEmpty: true,
            hasBlockedItems: false
        ), .skip(.startupSettling))
    }
}
