//
//  MenuBarItemSourcePIDResolverTests.swift
//  Project: Continuum
//
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Continuum
import XCTest

final class MenuBarItemSourcePIDResolverTests: XCTestCase {
    func testInProcessResolverHandlesEmptyBatchWithoutXPC() async {
        let pids = await MenuBarItem.sourcePIDsResolvingInProcess(for: [])

        XCTAssertEqual(pids, [])
    }
}
