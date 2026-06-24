//
//  SourcePIDSpatialMatchPolicyTests.swift
//  Project: Continuum
//
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Continuum
import XCTest

final class SourcePIDSpatialMatchPolicyTests: XCTestCase {
    private let controlCenterBundleID = "com.apple.controlcenter"

    func testAcceptsClearNearestNonControlCenterMatchWithNilTitle() {
        XCTAssertTrue(
            SourcePIDCache.SpatialMatchPolicy.acceptsClearNearest(
                bestDistance: 3,
                secondDistance: 23,
                bestBundleID: "com.openai.codex",
                windowTitle: nil,
                controlCenterBundleID: controlCenterBundleID
            )
        )
    }

    func testRejectsClearNearestWhenBestCandidateIsTooFar() {
        XCTAssertFalse(
            SourcePIDCache.SpatialMatchPolicy.acceptsClearNearest(
                bestDistance: 10.25,
                secondDistance: 23,
                bestBundleID: "com.Ebullioscopic.Atoll",
                windowTitle: nil,
                controlCenterBundleID: controlCenterBundleID
            )
        )
    }

    func testRejectsClearNearestWhenCandidateIsNotSeparatedEnough() {
        XCTAssertFalse(
            SourcePIDCache.SpatialMatchPolicy.acceptsClearNearest(
                bestDistance: 3,
                secondDistance: 9,
                bestBundleID: "com.example.first",
                windowTitle: nil,
                controlCenterBundleID: controlCenterBundleID
            )
        )
    }

    func testRejectsControlCenterMatchForNilTitle() {
        XCTAssertFalse(
            SourcePIDCache.SpatialMatchPolicy.acceptsClearNearest(
                bestDistance: 3,
                secondDistance: 23,
                bestBundleID: controlCenterBundleID,
                windowTitle: nil,
                controlCenterBundleID: controlCenterBundleID
            )
        )
    }

    func testRejectsControlCenterMatchForGenericTitle() {
        XCTAssertFalse(
            SourcePIDCache.SpatialMatchPolicy.acceptsClearNearest(
                bestDistance: 0,
                secondDistance: 40,
                bestBundleID: controlCenterBundleID,
                windowTitle: "Item-0",
                controlCenterBundleID: controlCenterBundleID
            )
        )
    }

    func testAcceptsControlCenterMatchForNamedTitle() {
        XCTAssertTrue(
            SourcePIDCache.SpatialMatchPolicy.acceptsClearNearest(
                bestDistance: 3,
                secondDistance: 23,
                bestBundleID: controlCenterBundleID,
                windowTitle: "WiFi",
                controlCenterBundleID: controlCenterBundleID
            )
        )
    }
}
