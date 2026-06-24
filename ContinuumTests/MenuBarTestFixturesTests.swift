//
//  MenuBarTestFixturesTests.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Continuum
import XCTest

/// Sanity tests for the synthetic fixture builders in
/// MenuBarTestFixtures.swift. These pin down that the fixtures produce values
/// with the documented defaults so the planner tests built on top of them stay
/// stable.
final class MenuBarTestFixturesTests: XCTestCase {
    func testAppItemTagBuildsExpectedNamespaceAndTitle() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status")
        XCTAssertEqual(String(describing: tag.namespace), "com.example.app")
        XCTAssertEqual(tag.title, "Status")
        XCTAssertEqual(tag.instanceIndex, 0)
        XCTAssertNil(tag.windowID)
    }

    func testAppItemTagSupportsInstanceIndex() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status", instanceIndex: 2)
        XCTAssertEqual(tag.instanceIndex, 2)
    }

    func testMenuBarItemFixtureDefaultsToMovableHideableItem() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status")
        let item = MenuBarItem.fixture(tag: tag, windowID: 42)

        XCTAssertEqual(item.windowID, 42)
        XCTAssertEqual(item.tag, tag)
        XCTAssertEqual(item.sourcePID, 1234)
        XCTAssertEqual(item.ownerPID, 1234)
        XCTAssertEqual(item.bounds, CGRect(x: 0, y: 0, width: 24, height: 22))
        XCTAssertTrue(item.isMovable)
        XCTAssertTrue(item.canBeHidden)
        XCTAssertFalse(item.isControlItem)
        XCTAssertTrue(item.isOnScreen)
    }

    func testMenuBarItemFixtureRespectsExplicitBounds() {
        let bounds = CGRect(x: 100, y: 0, width: 30, height: 22)
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 1,
            bounds: bounds
        )
        XCTAssertEqual(item.bounds, bounds)
    }

    func testLayoutEditorAllowsOrdinaryMovableUnresolvedItems() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.app"), title: "", windowID: 88),
            windowID: 88,
            ownerPID: 1234,
            sourcePID: nil,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 22),
            title: nil,
            isOnScreen: true
        )

        XCTAssertTrue(MenuBarLayoutEditorPolicy.isMovableItem(item))
    }

    func testLayoutEditorRejectsUnresolvedControlCenterPlaceholder() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "", windowID: 88),
            windowID: 88,
            ownerPID: 787,
            sourcePID: nil,
            bounds: CGRect(x: -4_030, y: 0, width: 5_006, height: 33),
            title: nil,
            isOnScreen: false
        )

        XCTAssertTrue(item.isUnresolvedControlCenterPlaceholder)
        XCTAssertFalse(item.canBeHidden)
        XCTAssertFalse(MenuBarLayoutEditorPolicy.isMovableItem(item))
    }

    func testLayoutEditorKeepsKnownImmovableItemsLocked() {
        let item = MenuBarItem(
            tag: .clock,
            windowID: 89,
            ownerPID: 787,
            sourcePID: nil,
            bounds: CGRect(x: 100, y: 0, width: 64, height: 22),
            title: "Clock",
            isOnScreen: true
        )

        XCTAssertFalse(MenuBarLayoutEditorPolicy.isMovableItem(item))
    }

    func testContinuumTitlelessItemIsStructural() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(Constants.bundleIdentifier), title: "", windowID: 90),
            windowID: 90,
            ownerPID: 787,
            sourcePID: ProcessInfo.processInfo.processIdentifier,
            bounds: CGRect(x: -4_053, y: 0, width: 23, height: 33),
            title: nil,
            isOnScreen: false
        )

        XCTAssertTrue(item.isContinuumStructuralItem)
    }

    func testOrdinaryTitlelessAppItemIsNotContinuumStructural() {
        let item = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.app"), title: "", windowID: 91),
            windowID: 91,
            ownerPID: 1234,
            sourcePID: 1234,
            bounds: CGRect(x: -4_030, y: 0, width: 28, height: 33),
            title: nil,
            isOnScreen: false
        )

        XCTAssertFalse(item.isContinuumStructuralItem)
    }

    func testControlItemPairFixtureWithoutAlwaysHidden() {
        let pair = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 500, y: 0, width: 24, height: 22)
        )

        XCTAssertEqual(pair.hidden.tag, .hiddenControlItem)
        XCTAssertEqual(pair.hidden.bounds.minX, 500)
        XCTAssertNil(pair.alwaysHidden)
    }

    func testControlItemPairFixtureWithAlwaysHidden() {
        let pair = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 500, y: 0, width: 24, height: 22),
            alwaysHiddenAt: CGRect(x: 200, y: 0, width: 24, height: 22)
        )

        XCTAssertEqual(pair.hidden.tag, .hiddenControlItem)
        XCTAssertEqual(pair.alwaysHidden?.tag, .alwaysHiddenControlItem)
        XCTAssertEqual(pair.alwaysHidden?.bounds.minX, 200)
    }

    func testControlItemPairFixtureWindowIDsAreDistinct() {
        let pair = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 500, y: 0, width: 24, height: 22),
            alwaysHiddenAt: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
        XCTAssertNotEqual(pair.hidden.windowID, pair.alwaysHidden?.windowID)
    }

    func testControlItemPairFallsBackToWindowIDsWhenSourcePIDAndTitlesAreUnavailable() {
        let hiddenWindowID: CGWindowID = 44
        let alwaysHiddenWindowID: CGWindowID = 45
        let hiddenCandidate = MenuBarItem(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "17", windowID: hiddenWindowID),
            windowID: hiddenWindowID,
            ownerPID: 787,
            sourcePID: nil,
            bounds: CGRect(x: 500, y: 0, width: 24, height: 22),
            title: nil,
            isOnScreen: true
        )
        let alwaysHiddenCandidate = MenuBarItem(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "18", windowID: alwaysHiddenWindowID),
            windowID: alwaysHiddenWindowID,
            ownerPID: 787,
            sourcePID: nil,
            bounds: CGRect(x: 200, y: 0, width: 24, height: 22),
            title: nil,
            isOnScreen: true
        )
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status", windowID: 46),
            windowID: 46
        )
        var items = [appItem, hiddenCandidate, alwaysHiddenCandidate]

        let pair = MenuBarControlItems(
            items: &items,
            hiddenControlItemWindowID: hiddenWindowID,
            alwaysHiddenControlItemWindowID: alwaysHiddenWindowID
        )

        XCTAssertEqual(pair?.hidden.windowID, hiddenWindowID)
        XCTAssertEqual(pair?.alwaysHidden?.windowID, alwaysHiddenWindowID)
        XCTAssertEqual(pair?.hidden.tag, .hiddenControlItem)
        XCTAssertEqual(pair?.alwaysHidden?.tag, .alwaysHiddenControlItem)
        XCTAssertEqual(items.map(\.windowID), [46])
    }

    func testControlItemPairReclassifiesVisibleControlItemByWindowIDWhenTitleIsUnavailable() {
        let visibleWindowID: CGWindowID = 43
        let hiddenWindowID: CGWindowID = 44
        let visibleCandidate = MenuBarItem(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "", windowID: visibleWindowID),
            windowID: visibleWindowID,
            ownerPID: 787,
            sourcePID: nil,
            bounds: CGRect(x: -4_053, y: 0, width: 23, height: 33),
            title: nil,
            isOnScreen: false
        )
        let hiddenCandidate = MenuBarItem(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "", windowID: hiddenWindowID),
            windowID: hiddenWindowID,
            ownerPID: 787,
            sourcePID: nil,
            bounds: CGRect(x: -4_002, y: 0, width: 5_006, height: 33),
            title: nil,
            isOnScreen: false
        )
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status", windowID: 46),
            windowID: 46
        )
        var items = [visibleCandidate, appItem, hiddenCandidate]

        let pair = MenuBarControlItems(
            items: &items,
            visibleControlItemWindowID: visibleWindowID,
            hiddenControlItemWindowID: hiddenWindowID
        )

        XCTAssertEqual(pair?.hidden.tag, .hiddenControlItem)
        let visibleItem = items.first { $0.windowID == visibleWindowID }
        XCTAssertEqual(visibleItem?.tag, .visibleControlItem)
        XCTAssertEqual(visibleItem?.title, ControlItem.Identifier.visible.rawValue)
        XCTAssertEqual(visibleItem?.sourcePID, ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(items.filter { !$0.isControlItem }.map(\.windowID), [46])
    }

    func testControlItemPairReclassifiesSmallContinuumStructuralItemAsVisibleControl() {
        let visibleWindowID: CGWindowID = 43
        let hiddenWindowID: CGWindowID = 44
        let visibleCandidate = MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(Constants.bundleIdentifier), title: "", windowID: visibleWindowID),
            windowID: visibleWindowID,
            ownerPID: 787,
            sourcePID: ProcessInfo.processInfo.processIdentifier,
            bounds: CGRect(x: -4_054, y: 4.5, width: 25, height: 24),
            title: nil,
            isOnScreen: false
        )
        let hiddenCandidate = MenuBarItem(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "", windowID: hiddenWindowID),
            windowID: hiddenWindowID,
            ownerPID: 787,
            sourcePID: nil,
            bounds: CGRect(x: -4_028, y: 4.5, width: 5_002, height: 24),
            title: nil,
            isOnScreen: false
        )
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status", windowID: 46),
            windowID: 46
        )
        var items = [visibleCandidate, appItem, hiddenCandidate]

        let pair = MenuBarControlItems(
            items: &items,
            hiddenControlItemWindowID: hiddenWindowID
        )

        XCTAssertEqual(pair?.hidden.tag, .hiddenControlItem)
        let visibleItem = items.first { $0.windowID == visibleWindowID }
        XCTAssertEqual(visibleItem?.tag, .visibleControlItem)
        XCTAssertEqual(visibleItem?.title, ControlItem.Identifier.visible.rawValue)
        XCTAssertEqual(visibleItem?.sourcePID, ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(items.filter { !$0.isControlItem }.map(\.windowID), [46])
    }

    func testControlItemPairFallsBackToWideHiddenDividerWhenIdentityIsUnavailable() {
        let hiddenCandidate = MenuBarItem(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "17", windowID: 44),
            windowID: 44,
            ownerPID: 787,
            sourcePID: nil,
            bounds: CGRect(x: -4_053, y: 0, width: 5_006, height: 33),
            title: nil,
            isOnScreen: false
        )
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status", windowID: 46),
            windowID: 46,
            bounds: CGRect(x: 1_200, y: 0, width: 24, height: 22)
        )
        var items = [hiddenCandidate, appItem]

        let pair = MenuBarControlItems(items: &items)

        XCTAssertEqual(pair?.hidden.windowID, 44)
        XCTAssertNil(pair?.alwaysHidden)
        XCTAssertEqual(items.map(\.windowID), [46])
    }

    func testControlItemPairTreatsSecondWideDividerAsAlwaysHidden() {
        let alwaysHiddenCandidate = MenuBarItem(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "16", windowID: 43),
            windowID: 43,
            ownerPID: 787,
            sourcePID: nil,
            bounds: CGRect(x: -8_200, y: 0, width: 4_000, height: 33),
            title: nil,
            isOnScreen: false
        )
        let hiddenCandidate = MenuBarItem(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "17", windowID: 44),
            windowID: 44,
            ownerPID: 787,
            sourcePID: nil,
            bounds: CGRect(x: -4_053, y: 0, width: 5_006, height: 33),
            title: nil,
            isOnScreen: false
        )
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status", windowID: 46),
            windowID: 46,
            bounds: CGRect(x: 1_200, y: 0, width: 24, height: 22)
        )
        var items = [alwaysHiddenCandidate, appItem, hiddenCandidate]

        let pair = MenuBarControlItems(items: &items)

        XCTAssertEqual(pair?.hidden.windowID, 44)
        XCTAssertEqual(pair?.alwaysHidden?.windowID, 43)
        XCTAssertEqual(items.map(\.windowID), [46])
    }
}
