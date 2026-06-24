//
//  PlanUnmanagedPlacementTests.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Continuum
import XCTest

/// Characterization tests for LayoutSolver.planUnmanagedPlacement.
///
/// Pins down the placement decision for items present in the live menu
/// bar but not covered by a saved layout. Saved positions win; otherwise
/// the user's MenuBarNewItemsPlacement preference applies; otherwise fall back
/// to the section default.
final class PlanUnmanagedPlacementTests: XCTestCase {
    /// All unmanaged items have saved positions → all placements are .saved.
    func testAllSavedReturnsSavedPlacements() {
        let saved: [String: [String]] = [
            "visible": ["com.a.app:A", "com.b.app:B"],
            "hidden": ["com.c.app:C"],
        ]
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: ["com.a.app:A", "com.c.app:C"],
            savedSectionOrder: saved,
            newItemsPlacement: placement,
            currentUIDs: Set(["com.a.app:A", "com.c.app:C"])
        )

        XCTAssertEqual(result["com.a.app:A"], .saved(section: .visible, index: 0))
        XCTAssertEqual(result["com.c.app:C"], .saved(section: .hidden, index: 0))
    }

    /// No saved positions, no anchor → all .newItemDefault in the
    /// new-items section.
    func testAllUnseenReturnsNewItemDefault() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: ["com.new.app:Status"],
            savedSectionOrder: [:],
            newItemsPlacement: placement,
            currentUIDs: ["com.new.app:Status"]
        )

        XCTAssertEqual(result["com.new.app:Status"], .newItemDefault(section: .hidden))
    }

    /// Mixed: one saved, one unseen → correct per-uid placements.
    func testMixedSavedAndUnseen() {
        let saved: [String: [String]] = [
            "visible": ["com.known.app:Status"],
        ]
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "hidden",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: ["com.known.app:Status", "com.new.app:Status"],
            savedSectionOrder: saved,
            newItemsPlacement: placement,
            currentUIDs: ["com.known.app:Status", "com.new.app:Status"]
        )

        XCTAssertEqual(result["com.known.app:Status"], .saved(section: .visible, index: 0))
        XCTAssertEqual(result["com.new.app:Status"], .newItemDefault(section: .hidden))
    }

    /// Multi-instance: only one instance is saved, the other instance is
    /// the unmanaged one. baseID fallback gives the unmanaged instance
    /// the saved position (treating them as fungible).
    func testMultiInstanceBaseIDFallback() {
        let saved: [String: [String]] = [
            "hidden": ["com.example.app:Status"], // saved without :N suffix
        ]
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: nil,
            relation: .sectionDefault
        )

        // A different instance index appears. Exact match fails, baseID
        // match succeeds → .saved.
        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: ["com.example.app:Status:7"],
            savedSectionOrder: saved,
            newItemsPlacement: placement,
            currentUIDs: ["com.example.app:Status:7"]
        )

        XCTAssertEqual(
            result["com.example.app:Status:7"],
            .saved(section: .hidden, index: 0),
            "unmanaged instance with matching baseID should use the saved slot"
        )
    }

    /// MenuBarNewItemsPlacement configured with an anchor that's currently
    /// present → .newItemAnchored returned for an unseen item.
    func testAnchorPlacementWhenAnchorPresent() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: "com.spotlight.app:Anchor",
            relation: .leftOfAnchor
        )

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: ["com.new.app:Status"],
            savedSectionOrder: [:],
            newItemsPlacement: placement,
            currentUIDs: ["com.new.app:Status", "com.spotlight.app:Anchor"]
        )

        XCTAssertEqual(
            result["com.new.app:Status"],
            .newItemAnchored(
                section: .visible,
                anchorUID: "com.spotlight.app:Anchor",
                relation: .leftOfAnchor
            )
        )
    }

    /// MenuBarNewItemsPlacement anchor configured but anchor item is absent from
    /// the current menu bar → fall back to .newItemDefault.
    func testAnchorAbsentFallsBackToDefault() {
        let placement = MenuBarNewItemsPlacement(
            sectionKey: "visible",
            anchorIdentifier: "com.absent.app:Anchor",
            relation: .leftOfAnchor
        )

        let result = LayoutSolver.planUnmanagedPlacement(
            unmanagedUIDs: ["com.new.app:Status"],
            savedSectionOrder: [:],
            newItemsPlacement: placement,
            currentUIDs: ["com.new.app:Status"]
        )

        XCTAssertEqual(result["com.new.app:Status"], .newItemDefault(section: .visible))
    }
}
