//
//  OnboardingMockupsTests.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
@testable import Continuum
import XCTest

// MARK: - MenuBarTint

final class MenuBarTintTests: XCTestCase {
    func testDarkColorScheme() {
        let tint = MenuBarTint(colorScheme: .dark)
        XCTAssertEqual(tint.background, Color.black.opacity(0.5))
        XCTAssertEqual(tint.label, .white)
    }

    func testLightColorScheme() {
        let tint = MenuBarTint(colorScheme: .light)
        XCTAssertEqual(tint.background, Color.white.opacity(0.6))
        XCTAssertEqual(tint.label, .black)
    }
}

// MARK: - MenuBarDemoItems

final class MenuBarDemoItemsTests: XCTestCase {
    func testHiddenSymbolsAreStable() {
        XCTAssertEqual(MenuBarDemoItems.hidden, ["wifi", "battery.100", "speaker.wave.2"])
    }
}

// MARK: - OnboardingZoomSpec

final class OnboardingZoomSpecTests: XCTestCase {
    func testNoneDoesNotZoom() {
        XCTAssertEqual(OnboardingZoomSpec.none.scale, 1)
        XCTAssertEqual(OnboardingZoomSpec.none.corner, .center)
    }

    func testFeatureTourZoomsTowardTopTrailing() {
        XCTAssertEqual(OnboardingZoomSpec.featureTour.scale, 2.0)
        XCTAssertEqual(OnboardingZoomSpec.featureTour.corner, UnitPoint(x: 1.1, y: 0.0))
    }
}

// MARK: - MockupTimeline

@MainActor
final class MockupTimelineTests: XCTestCase {
    func testRestartReturnsIncrementingGenerations() {
        let timeline = MockupTimeline()
        XCTAssertEqual(timeline.restart(), 1)
        XCTAssertEqual(timeline.restart(), 2)
        XCTAssertEqual(timeline.restart(), 3)
    }

    func testScheduleRunsActionForCurrentGeneration() {
        let timeline = MockupTimeline()
        let gen = timeline.restart()

        let expectation = expectation(description: "action runs")
        timeline.schedule(after: 0.01, generation: gen) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testScheduleDropsActionFromStaleGeneration() {
        let timeline = MockupTimeline()
        let staleGen = timeline.restart()
        timeline.restart()

        let notCalled = expectation(description: "stale action does not run")
        notCalled.isInverted = true
        timeline.schedule(after: 0.01, generation: staleGen) {
            notCalled.fulfill()
        }
        wait(for: [notCalled], timeout: 0.2)
    }
}

// MARK: - ManagementMockupModel

@MainActor
final class ManagementMockupModelTests: XCTestCase {
    func testRestartResetsToHidden() {
        let model = ManagementMockupModel()
        model.itemsHidden = false

        model.restart()

        XCTAssertTrue(model.itemsHidden)
    }

    func testToggleFlipsHiddenState() {
        let model = ManagementMockupModel()
        let initial = model.itemsHidden

        model.toggle()
        XCTAssertEqual(model.itemsHidden, !initial)

        model.toggle()
        XCTAssertEqual(model.itemsHidden, initial)
    }
}

