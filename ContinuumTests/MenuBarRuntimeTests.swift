//
//  MenuBarRuntimeTests.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Continuum
import AppKit
import Combine
import CoreGraphics
import XCTest

final class MenuBarRuntimeTests: XCTestCase {
    func testStableIdentityCanBePersistedAndMoved() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 10,
            sourcePID: 1234
        )

        XCTAssertEqual(item.identityConfidence, .stable)
        XCTAssertTrue(item.identityConfidence.allowsPersistence)
        XCTAssertTrue(item.identityConfidence.allowsAutomatedMove)
    }

    func testUnresolvedControlCenterPlaceholderIsObservationOnly() {
        let item = MenuBarItem.fixture(
            tag: MenuBarItemTag(
                namespace: .controlCenter,
                title: "Item-0",
                windowID: 20
            ),
            windowID: 20,
            sourcePID: nil,
            ownerPID: 999,
            title: "Item-0"
        )

        XCTAssertEqual(item.identityConfidence, .unresolved)
        XCTAssertFalse(item.identityConfidence.allowsPersistence)
        XCTAssertFalse(item.identityConfidence.allowsAutomatedMove)
    }

    func testStructuralControlItemsCanMoveButAreNotUserLayoutPersistence() {
        let item = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 21,
            sourcePID: nil
        )

        XCTAssertEqual(item.identityConfidence, .structural)
        XCTAssertFalse(item.identityConfidence.allowsPersistence)
        XCTAssertTrue(item.identityConfidence.allowsAutomatedMove)
    }

    func testControlItemDiscoveryPolicyReclassifiesOnlyWhenIdentityDiffers() {
        let processID: pid_t = 1234
        let expectedTitle = ControlItem.Identifier.hidden.rawValue
        let alreadyClassified = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 26,
            sourcePID: processID,
            title: expectedTitle
        )
        let staleTitle = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 27,
            sourcePID: processID,
            title: "Unexpected"
        )

        XCTAssertFalse(MenuBarControlItemDiscoveryPolicy.shouldReclassifyKnownControlItem(
            alreadyClassified,
            as: .hiddenControlItem,
            title: expectedTitle,
            processID: processID
        ))
        XCTAssertTrue(MenuBarControlItemDiscoveryPolicy.shouldReclassifyKnownControlItem(
            staleTitle,
            as: .hiddenControlItem,
            title: expectedTitle,
            processID: processID
        ))
        XCTAssertTrue(MenuBarControlItemDiscoveryPolicy.shouldReclassifyKnownControlItem(
            alreadyClassified,
            as: .alwaysHiddenControlItem,
            title: ControlItem.Identifier.alwaysHidden.rawValue,
            processID: processID
        ))
    }

    func testControlItemDiscoveryPolicyRecognizesVisibleFallback() {
        let visibleCandidate = MenuBarItem.fixture(
            tag: MenuBarItemTag(
                namespace: .string(Constants.bundleIdentifier),
                title: "",
                windowID: 28
            ),
            windowID: 28,
            bounds: CGRect(x: -4_054, y: 4.5, width: 25, height: 24),
            sourcePID: ProcessInfo.processInfo.processIdentifier,
            title: nil
        )
        let tooWide = MenuBarItem.fixture(
            tag: visibleCandidate.tag,
            windowID: 29,
            bounds: CGRect(x: -4_054, y: 4.5, width: 101, height: 24),
            sourcePID: ProcessInfo.processInfo.processIdentifier,
            title: nil
        )
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 30
        )

        XCTAssertTrue(MenuBarControlItemDiscoveryPolicy.isVisibleControlItemFallback(visibleCandidate))
        XCTAssertFalse(MenuBarControlItemDiscoveryPolicy.isVisibleControlItemFallback(tooWide))
        XCTAssertFalse(MenuBarControlItemDiscoveryPolicy.isVisibleControlItemFallback(appItem))
    }

    func testControlItemDiscoveryPolicyOrdersWideDividersRightToLeft() {
        let alwaysHiddenCandidate = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "16", windowID: 31),
            windowID: 31,
            bounds: CGRect(x: -8_200, y: 0, width: 4_000, height: 33),
            sourcePID: nil
        )
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status", windowID: 32),
            windowID: 32,
            bounds: CGRect(x: 1_200, y: 0, width: 24, height: 22)
        )
        let hiddenCandidate = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "17", windowID: 33),
            windowID: 33,
            bounds: CGRect(x: -4_053, y: 0, width: 5_006, height: 33),
            sourcePID: nil
        )

        let indices = MenuBarControlItemDiscoveryPolicy.wideDividerIndices(
            in: [alwaysHiddenCandidate, appItem, hiddenCandidate]
        )

        XCTAssertEqual(indices, [2, 0])
        XCTAssertEqual(MenuBarControlItemDiscoveryPolicy.adjustedIndexAfterRemoving(0, removedIndex: 2), 0)
        XCTAssertEqual(MenuBarControlItemDiscoveryPolicy.adjustedIndexAfterRemoving(2, removedIndex: 0), 1)
    }

    func testControlItemResolverUsesClassifiedTagsAndRemovesDividerItems() {
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status", windowID: 34),
            windowID: 34
        )
        let hidden = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 35,
            sourcePID: nil
        )
        let alwaysHidden = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 36,
            sourcePID: nil
        )
        var items = [appItem, hidden, alwaysHidden]

        let resolved = MenuBarControlItemResolver.resolve(items: &items)

        XCTAssertEqual(resolved?.hidden, hidden)
        XCTAssertEqual(resolved?.alwaysHidden, alwaysHidden)
        XCTAssertEqual(items, [appItem])
    }

    func testControlItemResolverReclassifiesKnownWindowIDs() throws {
        let processID: pid_t = 4_321
        let visible = MenuBarItem.fixture(
            tag: .appItem(bundleID: Constants.bundleIdentifier, title: "visible", windowID: 37),
            windowID: 37,
            sourcePID: nil,
            title: "stale"
        )
        let hidden = MenuBarItem.fixture(
            tag: .appItem(bundleID: Constants.bundleIdentifier, title: "hidden", windowID: 38),
            windowID: 38,
            sourcePID: nil,
            title: "stale"
        )
        let alwaysHidden = MenuBarItem.fixture(
            tag: .appItem(bundleID: Constants.bundleIdentifier, title: "alwaysHidden", windowID: 39),
            windowID: 39,
            sourcePID: nil,
            title: "stale"
        )
        var items = [visible, hidden, alwaysHidden]

        let resolved = try XCTUnwrap(MenuBarControlItemResolver.resolve(
            items: &items,
            visibleControlItemWindowID: visible.windowID,
            hiddenControlItemWindowID: hidden.windowID,
            alwaysHiddenControlItemWindowID: alwaysHidden.windowID,
            processID: processID
        ))

        XCTAssertEqual(resolved.hidden.tag, .hiddenControlItem)
        XCTAssertEqual(resolved.hidden.sourcePID, processID)
        XCTAssertEqual(resolved.hidden.title, ControlItem.Identifier.hidden.rawValue)
        XCTAssertEqual(resolved.alwaysHidden?.tag, .alwaysHiddenControlItem)
        XCTAssertEqual(items.map(\.tag), [.visibleControlItem])
        XCTAssertEqual(items.first?.sourcePID, processID)
    }

    func testControlItemWindowIDsCarryKnownDividerWindowsTogether() {
        let windowIDs = MenuBarControlItemWindowIDs(
            visible: 1_001,
            hidden: 1_002,
            alwaysHidden: 1_003
        )

        XCTAssertEqual(windowIDs.visible, 1_001)
        XCTAssertEqual(windowIDs.hidden, 1_002)
        XCTAssertEqual(windowIDs.alwaysHidden, 1_003)
        XCTAssertEqual(MenuBarControlItemWindowIDs.unresolved, MenuBarControlItemWindowIDs())
    }

    func testControlItemsRuntimeValuePreservesResolvedControls() {
        let hidden = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 47,
            sourcePID: nil
        )
        let alwaysHidden = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 48,
            sourcePID: nil
        )

        let controlItems = MenuBarControlItems(hidden: hidden, alwaysHidden: alwaysHidden)

        XCTAssertEqual(controlItems.hidden, hidden)
        XCTAssertEqual(controlItems.alwaysHidden, alwaysHidden)
    }

    func testControlItemsRuntimeValueResolvesFromWindowIDContext() throws {
        let hidden = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.helper", title: "hidden", windowID: 49),
            windowID: 49,
            sourcePID: nil
        )
        var items = [hidden]

        let controlItems = try XCTUnwrap(MenuBarControlItems(
            items: &items,
            windowIDs: MenuBarControlItemWindowIDs(hidden: hidden.windowID)
        ))

        XCTAssertEqual(controlItems.hidden.tag, .hiddenControlItem)
        XCTAssertEqual(controlItems.hidden.windowID, hidden.windowID)
        XCTAssertTrue(items.isEmpty)
    }

    func testControlItemOrderPolicySkipsWhenOrderIsAlreadyValid() {
        let withoutAlwaysHidden = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 100, y: 0, width: 24, height: 22)
        )
        let orderedRightToLeft = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 100, y: 0, width: 24, height: 22),
            alwaysHiddenAt: CGRect(x: 60, y: 0, width: 24, height: 22)
        )

        XCTAssertNil(MenuBarControlItemOrderPolicy.correctionDestination(for: withoutAlwaysHidden))
        XCTAssertNil(MenuBarControlItemOrderPolicy.correctionDestination(for: orderedRightToLeft))
        XCTAssertFalse(MenuBarControlItemOrderPolicy.requiresCorrection(
            hiddenBounds: orderedRightToLeft.hidden.bounds,
            alwaysHiddenBounds: orderedRightToLeft.alwaysHidden?.bounds
        ))
    }

    func testControlItemOrderPolicyMovesAlwaysHiddenLeftOfHiddenWhenReversed() throws {
        let reversed = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 60, y: 0, width: 24, height: 22),
            alwaysHiddenAt: CGRect(x: 100, y: 0, width: 24, height: 22)
        )

        let destination = try XCTUnwrap(
            MenuBarControlItemOrderPolicy.correctionDestination(for: reversed)
        )

        XCTAssertTrue(MenuBarControlItemOrderPolicy.requiresCorrection(
            hiddenBounds: reversed.hidden.bounds,
            alwaysHiddenBounds: reversed.alwaysHidden?.bounds
        ))
        switch destination {
        case let .leftOfItem(item):
            XCTAssertEqual(item, reversed.hidden)
        case .rightOfItem:
            XCTFail("Expected always-hidden control to move left of hidden control")
        }
    }

    func testControlItemResolverAcceptsWindowIDContext() throws {
        let processID: pid_t = 4_323
        let hidden = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.helper", title: "unclassified-hidden", windowID: 45),
            windowID: 45,
            sourcePID: nil
        )
        let alwaysHidden = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.helper", title: "unclassified-always", windowID: 46),
            windowID: 46,
            sourcePID: nil
        )
        var items = [hidden, alwaysHidden]

        let resolved = try XCTUnwrap(MenuBarControlItemResolver.resolve(
            items: &items,
            windowIDs: MenuBarControlItemWindowIDs(
                hidden: hidden.windowID,
                alwaysHidden: alwaysHidden.windowID
            ),
            processID: processID
        ))

        XCTAssertEqual(resolved.hidden.tag, .hiddenControlItem)
        XCTAssertEqual(resolved.hidden.sourcePID, processID)
        XCTAssertEqual(resolved.alwaysHidden?.tag, .alwaysHiddenControlItem)
        XCTAssertTrue(items.isEmpty)
    }

    func testControlItemResolverFallsBackToProcessOwnedTitles() throws {
        let processID: pid_t = 4_322
        let hidden = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.continuum-helper", title: "unclassified-hidden", windowID: 40),
            windowID: 40,
            sourcePID: processID,
            title: ControlItem.Identifier.hidden.rawValue
        )
        let alwaysHidden = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.continuum-helper", title: "unclassified-always", windowID: 41),
            windowID: 41,
            sourcePID: processID,
            title: ControlItem.Identifier.alwaysHidden.rawValue
        )
        var items = [hidden, alwaysHidden]

        let resolved = try XCTUnwrap(MenuBarControlItemResolver.resolve(
            items: &items,
            processID: processID
        ))

        XCTAssertEqual(resolved.hidden, hidden)
        XCTAssertEqual(resolved.alwaysHidden, alwaysHidden)
        XCTAssertTrue(items.isEmpty)
    }

    func testControlItemResolverFallsBackToWideDividerGeometry() throws {
        let alwaysHiddenCandidate = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "16", windowID: 42),
            windowID: 42,
            bounds: CGRect(x: -8_200, y: 0, width: 4_000, height: 33),
            sourcePID: nil
        )
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status", windowID: 43),
            windowID: 43,
            bounds: CGRect(x: 1_200, y: 0, width: 24, height: 22)
        )
        let hiddenCandidate = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "17", windowID: 44),
            windowID: 44,
            bounds: CGRect(x: -4_053, y: 0, width: 5_006, height: 33),
            sourcePID: nil
        )
        var items = [alwaysHiddenCandidate, appItem, hiddenCandidate]

        let resolved = try XCTUnwrap(MenuBarControlItemResolver.resolve(items: &items))

        XCTAssertEqual(resolved.hidden, hiddenCandidate)
        XCTAssertEqual(resolved.alwaysHidden, alwaysHiddenCandidate)
        XCTAssertEqual(items, [appItem])
    }

    @MainActor
    func testObservationRuntimeRetriesZeroItemRead() async throws {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status", windowID: 50),
            windowID: 50
        )
        var responses = [[MenuBarItem](), [item]]
        var requestedSourcePIDResolution = [Bool]()
        var sleepDurations = [Duration]()

        let outcome = await MenuBarObservationRuntime.observe(
            displayID: 1,
            currentItemWindowIDs: nil,
            previousWindowIDs: [],
            previousSourcePIDs: [:],
            knownItemIdentifiers: [],
            resolveSourcePID: true,
            itemProvider: { resolveSourcePID in
                requestedSourcePIDResolution.append(resolveSourcePID)
                return responses.removeFirst()
            },
            sleeper: { duration in
                sleepDurations.append(duration)
            },
            bundleIdentifierForPID: { _ in nil }
        )

        guard case let .observed(result) = outcome else {
            return XCTFail("Expected the retry to return an observation")
        }
        XCTAssertEqual(result.attempts, 2)
        XCTAssertEqual(result.items, [item])
        XCTAssertEqual(requestedSourcePIDResolution, [true, true])
        XCTAssertEqual(sleepDurations, [MenuBarObservationRetryPolicy.retryDelay])
    }

    @MainActor
    func testObservationRuntimeFailsAfterRepeatedZeroItemReads() async {
        var sleepDurations = [Duration]()

        let outcome = await MenuBarObservationRuntime.observe(
            displayID: 1,
            currentItemWindowIDs: nil,
            previousWindowIDs: [],
            previousSourcePIDs: [:],
            knownItemIdentifiers: [],
            resolveSourcePID: false,
            itemProvider: { _ in [] },
            sleeper: { duration in
                sleepDurations.append(duration)
            },
            bundleIdentifierForPID: { _ in nil }
        )

        guard case let .zeroItems(failure) = outcome else {
            return XCTFail("Expected repeated zero-item reads to fail")
        }
        XCTAssertEqual(failure.attempts, 2)
        XCTAssertEqual(failure.detail, MenuBarObservationRetryPolicy.exhaustedDetail)
        XCTAssertEqual(sleepDurations, [MenuBarObservationRetryPolicy.retryDelay])
    }

    @MainActor
    func testObservationRuntimeDropsClonesAndNormalizesWindowIDs() async throws {
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status", windowID: 60),
            windowID: 60
        )
        let clone = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clone", title: "System Status Item Clone", windowID: 61),
            windowID: 61,
            title: "System Status Item Clone"
        )

        let outcome = await MenuBarObservationRuntime.observe(
            displayID: 2,
            currentItemWindowIDs: [61, 60],
            previousWindowIDs: [],
            previousSourcePIDs: [:],
            knownItemIdentifiers: [],
            resolveSourcePID: false,
            itemProvider: { _ in [clone, appItem] },
            sleeper: { _ in },
            bundleIdentifierForPID: { _ in nil }
        )

        guard case let .observed(result) = outcome else {
            return XCTFail("Expected clone-filtered observation")
        }
        XCTAssertEqual(result.items, [appItem])
        XCTAssertEqual(result.observation.cloneCount, 1)
        XCTAssertEqual(result.observation.droppedCloneWindowIDs, [61])
        XCTAssertEqual(result.observation.normalizedWindowIDs, [60])
    }

    @MainActor
    func testObservationRuntimeReconcilesSourcePIDsAndSeedsIdentifiers() async throws {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.observed.app", title: "Status", windowID: 70),
            windowID: 70,
            sourcePID: 2_222
        )

        let outcome = await MenuBarObservationRuntime.observe(
            displayID: 3,
            currentItemWindowIDs: nil,
            previousWindowIDs: [70],
            previousSourcePIDs: [70: 1_111],
            knownItemIdentifiers: [],
            resolveSourcePID: true,
            itemProvider: { _ in [item] },
            sleeper: { _ in },
            bundleIdentifierForPID: { pid in
                pid == 1_111 ? "com.correct.app" : nil
            }
        )

        guard case let .observed(result) = outcome else {
            return XCTFail("Expected reconciled observation")
        }
        let reconciledItem = try XCTUnwrap(result.items.first)
        XCTAssertEqual(reconciledItem.sourcePID, 1_111)
        XCTAssertEqual(reconciledItem.tag.namespace, .string("com.correct.app"))
        XCTAssertEqual(result.identityCorrections.count, 1)
        XCTAssertEqual(result.identityCorrections.first?.observedPID, 2_222)
        XCTAssertEqual(result.identifiersToSeed, ["com.correct.app:Status"])
    }

    @MainActor
    func testObservationRuntimeSupportsMutationReadsWithoutIdentityBaseline() async throws {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.observed.app", title: "Status", windowID: 71),
            windowID: 71,
            sourcePID: 2_222
        )

        let outcome = await MenuBarObservationRuntime.observe(
            displayID: 3,
            resolveSourcePID: true,
            itemProvider: { _ in [item] },
            sleeper: { _ in }
        )

        guard case let .observed(result) = outcome else {
            return XCTFail("Expected mutation-style observation")
        }
        XCTAssertEqual(result.items, [item])
        XCTAssertTrue(result.identityCorrections.isEmpty)
        XCTAssertTrue(result.identifiersToSeed.isEmpty)
    }

    func testSectionClassificationPolicyFiltersUncacheableItems() {
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 34
        )
        let visibleControl = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 35,
            sourcePID: nil
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 36,
            sourcePID: nil
        )
        let systemClone = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clone", title: "System Status Item Clone"),
            windowID: 37,
            title: "System Status Item Clone"
        )

        XCTAssertTrue(MenuBarSectionClassificationPolicy.isCacheable(appItem))
        XCTAssertTrue(MenuBarSectionClassificationPolicy.isCacheable(visibleControl))
        XCTAssertFalse(MenuBarSectionClassificationPolicy.isCacheable(hiddenControl))
        XCTAssertFalse(MenuBarSectionClassificationPolicy.isCacheable(systemClone))
    }

    func testSectionClassificationPolicyUsesStrictSectionBoundaries() {
        let hiddenControlBounds = CGRect(x: 100, y: 0, width: 10, height: 22)
        let alwaysHiddenControlBounds = CGRect(x: 40, y: 0, width: 10, height: 22)

        XCTAssertEqual(
            MenuBarSectionClassificationPolicy.section(
                for: CGRect(x: 120, y: 0, width: 20, height: 22),
                hiddenControlItemBounds: hiddenControlBounds,
                alwaysHiddenControlItemBounds: alwaysHiddenControlBounds
            ),
            .visible
        )
        XCTAssertEqual(
            MenuBarSectionClassificationPolicy.section(
                for: CGRect(x: 60, y: 0, width: 20, height: 22),
                hiddenControlItemBounds: hiddenControlBounds,
                alwaysHiddenControlItemBounds: alwaysHiddenControlBounds
            ),
            .hidden
        )
        XCTAssertEqual(
            MenuBarSectionClassificationPolicy.section(
                for: CGRect(x: 10, y: 0, width: 20, height: 22),
                hiddenControlItemBounds: hiddenControlBounds,
                alwaysHiddenControlItemBounds: alwaysHiddenControlBounds
            ),
            .alwaysHidden
        )
        XCTAssertEqual(
            MenuBarSectionClassificationPolicy.section(
                for: CGRect(x: 10, y: 0, width: 20, height: 22),
                hiddenControlItemBounds: hiddenControlBounds,
                alwaysHiddenControlItemBounds: nil
            ),
            .hidden
        )
    }

    func testSectionClassificationPolicyUsesMidpointForStraddlingBounds() {
        let hiddenControlBounds = CGRect(x: 100, y: 0, width: 10, height: 22)
        let alwaysHiddenControlBounds = CGRect(x: 40, y: 0, width: 10, height: 22)

        XCTAssertEqual(
            MenuBarSectionClassificationPolicy.section(
                for: CGRect(x: 98, y: 0, width: 16, height: 22),
                hiddenControlItemBounds: hiddenControlBounds,
                alwaysHiddenControlItemBounds: alwaysHiddenControlBounds
            ),
            .visible
        )
        XCTAssertEqual(
            MenuBarSectionClassificationPolicy.section(
                for: CGRect(x: 90, y: 0, width: 20, height: 22),
                hiddenControlItemBounds: hiddenControlBounds,
                alwaysHiddenControlItemBounds: alwaysHiddenControlBounds
            ),
            .hidden
        )
        XCTAssertEqual(
            MenuBarSectionClassificationPolicy.section(
                for: CGRect(x: 30, y: 0, width: 20, height: 22),
                hiddenControlItemBounds: hiddenControlBounds,
                alwaysHiddenControlItemBounds: alwaysHiddenControlBounds
            ),
            .alwaysHidden
        )
    }

    func testCachePopulationPolicyAdmissionRejectsInvalidAndDuplicateItems() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 38
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 39,
            sourcePID: nil
        )

        XCTAssertEqual(
            MenuBarCachePopulationPolicy.admissionDecision(for: item, seenTags: []),
            .admit
        )
        XCTAssertEqual(
            MenuBarCachePopulationPolicy.admissionDecision(for: item, seenTags: [item.tag]),
            .rejectDuplicate
        )
        XCTAssertEqual(
            MenuBarCachePopulationPolicy.admissionDecision(for: hiddenControl, seenTags: []),
            .rejectUncacheable
        )
    }

    func testEventErrorRuntimeValueDescribesOperationFailures() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.event", title: "Event Item"),
            windowID: 39
        )

        XCTAssertEqual(
            MenuBarEventError.cannotComplete.description,
            "MenuBarEventError.cannotComplete"
        )
        XCTAssertEqual(
            MenuBarEventError.eventCreationFailure(item).description,
            "MenuBarEventError.eventCreationFailure(item: \(item.tag))"
        )
        XCTAssertEqual(
            MenuBarEventError.missingItemBounds(item).errorDescription,
            "Missing bounds rectangle for \"\(item.displayName)\""
        )
    }

    func testEventErrorRuntimeValueGuidesRecoveryByFailureKind() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.event", title: "Event Item"),
            windowID: 40
        )

        XCTAssertNil(MenuBarEventError.itemNotMovable(item).recoverySuggestion)
        XCTAssertEqual(
            MenuBarEventError.eventOperationTimeout(item).recoverySuggestion,
            "Please try again. If the error persists, please file a bug report."
        )
        XCTAssertEqual(
            MenuBarEventError.invalidEventSource.errorDescription,
            "Invalid event source"
        )
    }

    func testSyntheticEventTypeMapsMoveAndClickContracts() {
        let moveDown = MenuBarSyntheticEventType.move(.mouseDown)
        let moveUp = MenuBarSyntheticEventType.move(.mouseUp)
        let rightClickDown = MenuBarSyntheticEventType.click(.rightMouseDown)
        let otherClickUp = MenuBarSyntheticEventType.click(.otherMouseUp)

        XCTAssertEqual(moveDown.cgEventType, .leftMouseDown)
        XCTAssertEqual(moveUp.cgEventType, .leftMouseUp)
        XCTAssertEqual(moveDown.cgMouseButton, .left)
        XCTAssertTrue(moveDown.cgEventFlags.contains(.maskCommand))
        XCTAssertFalse(moveUp.cgEventFlags.contains(.maskCommand))
        XCTAssertEqual(rightClickDown.cgEventType, .rightMouseDown)
        XCTAssertEqual(rightClickDown.cgMouseButton, .right)
        XCTAssertEqual(otherClickUp.cgEventType, .otherMouseUp)
        XCTAssertEqual(otherClickUp.cgMouseButton, .center)

        let left = MenuBarSyntheticEventType.clickSubtypes(for: .left)
        XCTAssertEqual(left.down, .leftMouseDown)
        XCTAssertEqual(left.up, .leftMouseUp)

        let right = MenuBarSyntheticEventType.clickSubtypes(for: .right)
        XCTAssertEqual(right.down, .rightMouseDown)
        XCTAssertEqual(right.up, .rightMouseUp)

        let other = MenuBarSyntheticEventType.clickSubtypes(for: .center)
        XCTAssertEqual(other.down, .otherMouseDown)
        XCTAssertEqual(other.up, .otherMouseUp)
    }

    func testEventContinuationModeDefinesRelayTopologyAndTimeout() {
        XCTAssertFalse(MenuBarEventContinuationMode.postEventBarrier.requiresFirstLocationRelayTap)
        XCTAssertTrue(MenuBarEventContinuationMode.scromble.requiresFirstLocationRelayTap)
        XCTAssertEqual(
            MenuBarEventContinuationMode.postEventBarrier.operationTimeout(
                base: .milliseconds(120),
                repeatCount: 2
            ),
            .milliseconds(240)
        )
        XCTAssertEqual(
            MenuBarEventContinuationMode.scromble.operationTimeout(
                base: .milliseconds(80),
                repeatCount: 3
            ),
            .milliseconds(240)
        )
    }

    func testEventSourceRuntimeCreatesSourcesAndPermitsLocalEvents() throws {
        _ = try MenuBarEventSourceRuntime.source()
        XCTAssertNoThrow(try MenuBarEventSourceRuntime.permitLocalEvents())
    }

    func testSyntheticEventFactoryCreatesMoveEventWithStableFields() throws {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.move-event", title: "Move Event"),
            windowID: 321
        )
        let source = try MenuBarEventSourceRuntime.source()
        let event = try XCTUnwrap(
            CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .move(.mouseDown),
                location: CGPoint(x: 44, y: 55)
            )
        )

        XCTAssertEqual(event.type, .leftMouseDown)
        XCTAssertEqual(event.location, CGPoint(x: 44, y: 55))
        XCTAssertTrue(event.flags.contains(.maskCommand))
        XCTAssertEqual(event.getIntegerValueField(.mouseEventWindowUnderMousePointer), 321)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent), 321)
        XCTAssertEqual(event.getIntegerValueField(.windowID), 321)
        XCTAssertTrue(event.matches(event, byIntegerFields: CGEventField.menuBarItemEventFields))
    }

    func testSyntheticEventFactoryCreatesClickEventWithClickState() throws {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.click-event", title: "Click Event"),
            windowID: 322
        )
        let source = try MenuBarEventSourceRuntime.source()
        let event = try XCTUnwrap(
            CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .click(.rightMouseDown),
                location: CGPoint(x: 66, y: 77)
            )
        )
        let nullEventA = try XCTUnwrap(CGEvent.uniqueNullEvent())
        let nullEventB = try XCTUnwrap(CGEvent.uniqueNullEvent())

        XCTAssertEqual(event.type, .rightMouseDown)
        XCTAssertEqual(event.location, CGPoint(x: 66, y: 77))
        XCTAssertFalse(event.flags.contains(.maskCommand))
        XCTAssertEqual(event.getIntegerValueField(.mouseEventWindowUnderMousePointer), 322)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent), 322)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventClickState), 1)

        event.setTargetPID(123)
        XCTAssertEqual(event.getIntegerValueField(.eventTargetUnixProcessID), 123)
        XCTAssertFalse(
            nullEventA.matches(
                nullEventB,
                byIntegerFields: [.eventSourceUserData]
            )
        )
    }

    func testMoveDestinationRuntimeValueCarriesTargetAndSide() {
        let target = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.target", title: "Target"),
            windowID: 39
        )

        let left = MenuBarMoveDestination.leftOfItem(target)
        let right = MenuBarMoveDestination.rightOfItem(target)

        XCTAssertEqual(left.targetItem, target)
        XCTAssertTrue(left.isLeftOfTarget)
        XCTAssertFalse(left.isRightOfTarget)
        XCTAssertEqual(left.logString, "left of \(target.logString)")
        XCTAssertEqual(right.targetItem, target)
        XCTAssertFalse(right.isLeftOfTarget)
        XCTAssertTrue(right.isRightOfTarget)
        XCTAssertEqual(right.logString, "right of \(target.logString)")
    }

    func testItemCacheRuntimeValueInsertsByMoveDestination() {
        let visibleAnchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 40
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 41,
            sourcePID: nil
        )
        let alwaysHiddenControl = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 42,
            sourcePID: nil
        )
        let leftItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.left", title: "Left"),
            windowID: 43
        )
        let rightItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.right", title: "Right"),
            windowID: 44
        )
        let hiddenItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.hidden", title: "Hidden"),
            windowID: 45
        )

        var cache = MenuBarItemCache(displayID: 84)
        cache[.visible] = [visibleAnchor]
        cache[.hidden] = [hiddenControl]
        cache[.alwaysHidden] = [alwaysHiddenControl]

        cache.insert(leftItem, at: .leftOfItem(visibleAnchor))
        cache.insert(rightItem, at: .rightOfItem(visibleAnchor))
        cache.insert(hiddenItem, at: .leftOfItem(hiddenControl))

        XCTAssertEqual(cache.displayID, 84)
        XCTAssertEqual(cache[.visible], [leftItem, visibleAnchor, rightItem])
        XCTAssertEqual(cache[.hidden], [hiddenControl, hiddenItem])
        XCTAssertEqual(cache[.alwaysHidden], [alwaysHiddenControl])
        XCTAssertEqual(cache.managedItems, [leftItem, visibleAnchor, rightItem, hiddenControl, hiddenItem, alwaysHiddenControl])
    }

    func testLayoutEditorPolicyBuildsSnapshotFromSavedOrderAndLiveCache() {
        let visible = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.visible", title: "Visible"),
            windowID: 50,
            sourcePID: 5_001
        )
        let hidden = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.hidden", title: "Hidden"),
            windowID: 51,
            sourcePID: nil
        )
        let closedIdentifier = "com.example.closed:Closed"
        var cache = MenuBarItemCache(displayID: 12)
        cache[.visible] = [visible]
        cache[.hidden] = [hidden]

        let snapshot = MenuBarLayoutEditorPolicy.snapshot(
            cache: cache,
            savedSectionOrder: [
                MenuBarSavedOrderPolicy.sectionKey(for: .visible): [
                    visible.uniqueIdentifier,
                    closedIdentifier,
                ],
            ],
            fallbackSectionOrder: [
                MenuBarSavedOrderPolicy.sectionKey(for: .hidden): [hidden.uniqueIdentifier],
            ]
        )

        XCTAssertEqual(
            snapshot.sections[.visible]?.map(\.id),
            [visible.uniqueIdentifier, closedIdentifier]
        )
        XCTAssertEqual(snapshot.sections[.hidden]?.map(\.id), [hidden.uniqueIdentifier])

        let liveItem = snapshot.sections[.visible]?.first
        XCTAssertEqual(liveItem?.id, visible.uniqueIdentifier)
        XCTAssertEqual(liveItem?.iconProcessIdentifier, 5_001)
        XCTAssertTrue(liveItem?.isAvailable == true)
        XCTAssertTrue(liveItem?.isMovable == true)
        XCTAssertTrue(liveItem?.isIdentityResolved == true)

        let closedItem = snapshot.sections[.visible]?.last
        XCTAssertEqual(closedItem?.title, "Closed")
        XCTAssertEqual(closedItem?.subtitle, "Saved item")
        XCTAssertEqual(closedItem?.iconBundleIdentifier, "com.example.closed")
        XCTAssertFalse(closedItem?.isAvailable == true)
    }

    func testLayoutEditorPolicyDropsLiveAliasesAndPrunableSavedIdentifiers() {
        let live = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.alias", title: "Alias"),
            windowID: 52
        )
        let staleAliasIdentifier = "com.example.alias:Alias:4"
        var cache = MenuBarItemCache(displayID: 13)
        cache[.visible] = [live]

        let snapshot = MenuBarLayoutEditorPolicy.snapshot(
            cache: cache,
            savedSectionOrder: [
                MenuBarSavedOrderPolicy.sectionKey(for: .visible): [
                    staleAliasIdentifier,
                    "com.apple.controlcenter:Item-0",
                    live.uniqueIdentifier,
                ],
            ],
            fallbackSectionOrder: [:]
        )

        XCTAssertEqual(snapshot.sections[.visible]?.map(\.id), [live.uniqueIdentifier])
    }

    func testSystemMenuExtraMetadataResolvesNamesAndSymbols() {
        XCTAssertEqual(
            MenuBarSystemMenuExtraMetadata.displayName(
                namespace: "com.apple.controlcenter",
                title: "WiFi"
            ),
            "Wi-Fi"
        )
        XCTAssertEqual(
            MenuBarSystemMenuExtraMetadata.displayName(
                namespace: "com.apple.systemuiserver",
                title: "com.apple.menuextra.TimeMachine"
            ),
            "Time Machine"
        )
        XCTAssertEqual(
            MenuBarSystemMenuExtraMetadata.symbolName(
                namespace: "com.apple.controlcenter",
                title: "ScreenMirroring"
            ),
            "rectangle.on.rectangle"
        )
        XCTAssertNil(
            MenuBarSystemMenuExtraMetadata.displayName(
                namespace: "com.apple.controlcenter",
                title: "Item-0"
            )
        )
    }

    func testCachePopulationPolicyTemporaryDestinationUsesExactTagMatch() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.temp", title: "Temp", windowID: 40),
            windowID: 40,
            sourcePID: 4_001
        )
        let target = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 41,
            sourcePID: nil
        )
        let destination = MenuBarMoveDestination.leftOfItem(target)

        let resolved = MenuBarCachePopulationPolicy.temporaryDestination(
            for: item,
            currentSection: .hidden,
            contexts: [
                .init(
                    tag: item.tag,
                    sourcePID: 4_001,
                    originalSection: .alwaysHidden,
                    destination: destination
                ),
            ]
        )

        XCTAssertEqual(resolved, destination)
    }

    func testCachePopulationPolicyTemporaryDestinationUsesVisiblePIDFallback() {
        let originalTag = MenuBarItemTag.appItem(
            bundleID: "com.example.temp",
            title: "Temp",
            windowID: 42
        )
        let currentTag = MenuBarItemTag.appItem(
            bundleID: "com.example.temp",
            title: "Temp",
            windowID: 43
        )
        let item = MenuBarItem.fixture(
            tag: currentTag,
            windowID: 43,
            sourcePID: 4_002
        )
        let target = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 44,
            sourcePID: nil
        )
        let destination = MenuBarMoveDestination.rightOfItem(target)
        let contexts = [
            MenuBarCachePopulationPolicy.TemporaryContext(
                tag: originalTag,
                sourcePID: 4_002,
                originalSection: .hidden,
                destination: destination
            ),
        ]

        XCTAssertEqual(
            MenuBarCachePopulationPolicy.temporaryDestination(
                for: item,
                currentSection: .visible,
                contexts: contexts
            ),
            destination
        )
        XCTAssertNil(
            MenuBarCachePopulationPolicy.temporaryDestination(
                for: item,
                currentSection: .hidden,
                contexts: contexts
            )
        )
    }

    func testCachePopulationPolicyTemporaryDestinationRejectsVisibleOriginalSectionFallback() {
        let originalTag = MenuBarItemTag.appItem(
            bundleID: "com.example.temp",
            title: "Temp",
            windowID: 45
        )
        let currentTag = MenuBarItemTag.appItem(
            bundleID: "com.example.temp",
            title: "Temp",
            windowID: 46
        )
        let item = MenuBarItem.fixture(
            tag: currentTag,
            windowID: 46,
            sourcePID: 4_003
        )
        let target = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 47,
            sourcePID: nil
        )

        let resolved = MenuBarCachePopulationPolicy.temporaryDestination(
            for: item,
            currentSection: .visible,
            contexts: [
                .init(
                    tag: originalTag,
                    sourcePID: 4_003,
                    originalSection: .visible,
                    destination: .leftOfItem(target)
                ),
            ]
        )

        XCTAssertNil(resolved)
    }

    func testCachePopulationPolicyNoSectionFallbackDistinguishesBlockedItems() {
        XCTAssertEqual(
            MenuBarCachePopulationPolicy.noSectionFallback(
                for: CGRect(x: -1, y: 0, width: 24, height: 22)
            ),
            .skipBlocked
        )
        XCTAssertEqual(
            MenuBarCachePopulationPolicy.noSectionFallback(
                for: CGRect(x: 12, y: 0, width: 24, height: 22)
            ),
            .cacheInHidden
        )
    }

    func testCachePopulationRuntimeBuildsCacheBySection() {
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 100, y: 0, width: 10, height: 22),
            alwaysHiddenAt: CGRect(x: 40, y: 0, width: 10, height: 22)
        )
        let visible = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.visible", title: "Visible"),
            windowID: 48,
            bounds: CGRect(x: 120, y: 0, width: 20, height: 22)
        )
        let hidden = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.hidden", title: "Hidden"),
            windowID: 49,
            bounds: CGRect(x: 70, y: 0, width: 20, height: 22)
        )
        let alwaysHidden = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.always", title: "Always"),
            windowID: 50,
            bounds: CGRect(x: 10, y: 0, width: 20, height: 22)
        )

        let result = MenuBarCachePopulationRuntime.buildCache(
            items: [visible, hidden, alwaysHidden],
            controlItems: controlItems,
            displayID: 12,
            temporaryContexts: [],
            currentBoundsForItem: { $0.bounds }
        )

        XCTAssertEqual(result.cache.displayID, 12)
        XCTAssertEqual(result.cache[.visible], [visible])
        XCTAssertEqual(result.cache[.hidden], [hidden])
        XCTAssertEqual(result.cache[.alwaysHidden], [alwaysHidden])
        XCTAssertEqual(result.validCount, 3)
        XCTAssertEqual(result.invalidCount, 0)
        XCTAssertTrue(result.duplicateItems.isEmpty)
        XCTAssertEqual(result.temporarilyShownCount, 0)
    }

    func testCachePopulationRuntimeFiltersDuplicatesAndUncacheableItems() {
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 100, y: 0, width: 10, height: 22)
        )
        let kept = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.kept", title: "Status"),
            windowID: 51,
            bounds: CGRect(x: 70, y: 0, width: 20, height: 22),
            sourcePID: nil
        )
        let duplicate = MenuBarItem.fixture(
            tag: kept.tag,
            windowID: 52,
            bounds: CGRect(x: 60, y: 0, width: 20, height: 22)
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 53,
            bounds: CGRect(x: 100, y: 0, width: 10, height: 22),
            sourcePID: nil
        )

        let result = MenuBarCachePopulationRuntime.buildCache(
            items: [kept, duplicate, hiddenControl],
            controlItems: controlItems,
            displayID: nil,
            temporaryContexts: [],
            currentBoundsForItem: { $0.bounds }
        )

        XCTAssertEqual(result.cache[.hidden], [kept])
        XCTAssertEqual(result.validCount, 1)
        XCTAssertEqual(result.invalidCount, 1)
        XCTAssertEqual(result.duplicateItems, [duplicate])
        XCTAssertEqual(result.missingSourcePIDItems, [kept])
    }

    func testCachePopulationRuntimeCachesTemporarilyShownItemsAtReturnDestination() {
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 100, y: 0, width: 10, height: 22)
        )
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.temp", title: "Temp", windowID: 54),
            windowID: 54,
            bounds: CGRect(x: 120, y: 0, width: 20, height: 22),
            sourcePID: 4_004
        )
        let destination = MenuBarMoveDestination.leftOfItem(controlItems.hidden)

        let result = MenuBarCachePopulationRuntime.buildCache(
            items: [item],
            controlItems: controlItems,
            displayID: nil,
            temporaryContexts: [
                .init(
                    tag: item.tag,
                    sourcePID: 4_004,
                    originalSection: .hidden,
                    destination: destination
                ),
            ],
            currentBoundsForItem: { $0.bounds }
        )

        XCTAssertTrue(result.cache[.visible].isEmpty)
        XCTAssertEqual(result.cache[.hidden], [item])
        XCTAssertEqual(result.temporarilyShownCount, 1)
    }

    func testIdentityReconcilerKeepsPreviousPIDWhenObservationDrifts() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.observed", title: "Clock"),
            windowID: 22,
            sourcePID: 2222
        )

        let result = MenuBarIdentityReconciler.reconcile(
            items: [item],
            previousSourcePIDs: [22: 1111],
            bundleIdentifierForPID: { pid in
                pid == 1111 ? "com.example.previous" : nil
            }
        )

        XCTAssertEqual(result.correctionCount, 1)
        XCTAssertEqual(result.items.first?.sourcePID, 1111)
        XCTAssertEqual(result.items.first?.tag.namespace, .string("com.example.previous"))
        XCTAssertEqual(result.items.first?.uniqueIdentifier, "com.example.previous:Clock")
        XCTAssertEqual(
            result.corrections,
            [
                MenuBarIdentityReconciler.Correction(
                    windowID: 22,
                    previousPID: 1111,
                    observedPID: 2222,
                    correctedNamespace: .string("com.example.previous")
                ),
            ]
        )
    }

    func testIdentityReconcilerKeepsNamespaceWhenPreviousBundleIsUnavailable() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.observed", title: "Clock"),
            windowID: 23,
            sourcePID: 2222
        )

        let result = MenuBarIdentityReconciler.reconcile(
            items: [item],
            previousSourcePIDs: [23: 1111],
            bundleIdentifierForPID: { _ in nil }
        )

        XCTAssertEqual(result.correctionCount, 1)
        XCTAssertEqual(result.items.first?.sourcePID, 1111)
        XCTAssertEqual(result.items.first?.tag.namespace, .string("com.example.observed"))
    }

    func testIdentityReconcilerDoesNotRewriteControlItemsOrUnresolvedItems() {
        let control = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 24,
            sourcePID: nil
        )
        let unresolved = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.unresolved", title: "Clock"),
            windowID: 25,
            sourcePID: nil
        )

        let result = MenuBarIdentityReconciler.reconcile(
            items: [control, unresolved],
            previousSourcePIDs: [
                24: 1111,
                25: 1111,
            ],
            bundleIdentifierForPID: { _ in "com.example.previous" }
        )

        XCTAssertTrue(result.corrections.isEmpty)
        XCTAssertEqual(result.items, [control, unresolved])
    }

    func testSnapshotBuildsStableInventoryFromItemCache() {
        let stable = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 30,
            bounds: CGRect(x: 800, y: 0, width: 24, height: 22),
            sourcePID: 1234
        )
        let unresolved = MenuBarItem.fixture(
            tag: MenuBarItemTag(
                namespace: .controlCenter,
                title: "Item-0",
                windowID: 31
            ),
            windowID: 31,
            bounds: CGRect(x: 824, y: 0, width: 24, height: 22),
            sourcePID: nil,
            ownerPID: 999,
            title: "Item-0"
        )
        var cache = MenuBarItemCache(displayID: 42)
        cache[.visible] = [stable]
        cache[.hidden] = [unresolved]

        let snapshot = MenuBarSnapshot(
            cache: cache,
            controlItemsMissing: false,
            systemMenuBarHidden: false,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertTrue(snapshot.isActionable)
        XCTAssertEqual(snapshot.displayID, 42)
        XCTAssertEqual(snapshot.itemCount, 2)
        XCTAssertTrue(snapshot.items.first { $0.itemIdentifier == stable.uniqueIdentifier }?.isOnScreen == true)
        XCTAssertEqual(snapshot.persistableItems.map(\.itemIdentifier), [stable.uniqueIdentifier])
        XCTAssertEqual(snapshot.movableItems.map(\.itemIdentifier), [stable.uniqueIdentifier])
        XCTAssertEqual(snapshot.unresolvedItems.map(\.itemIdentifier), [unresolved.uniqueIdentifier])
    }

    func testRuntimeCommandPolicyAllowsVisibleActivationWhileControlsAreMissing() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 33,
            sourcePID: 1234,
            isOnScreen: true
        )
        var cache = MenuBarItemCache(displayID: 42)
        cache[.visible] = [item]
        let failure = MenuBarRuntimeFailure(
            reason: .missingControlItems,
            detail: "hidden control item missing",
            occurredAt: Date(timeIntervalSince1970: 8)
        )
        let inventory = MenuBarRuntimeInventory(
            state: .degraded(failure),
            snapshot: MenuBarSnapshot(
                cache: cache,
                controlItemsMissing: true,
                systemMenuBarHidden: false
            )
        )

        XCTAssertEqual(
            MenuBarRuntimeCommandPolicy.activationDecision(
                itemIdentifier: item.uniqueIdentifier,
                inventory: inventory,
                itemIsOnScreen: true
            ),
            .allow(.clickInPlace)
        )
    }

    func testRuntimeCommandPolicyRejectsActivationWhenSystemMenuBarIsHidden() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 38,
            sourcePID: 1234,
            isOnScreen: true
        )
        var cache = MenuBarItemCache(displayID: 42)
        cache[.visible] = [item]
        let inventory = MenuBarRuntimeInventory(
            state: .idle,
            snapshot: MenuBarSnapshot(
                cache: cache,
                controlItemsMissing: false,
                systemMenuBarHidden: true
            )
        )

        XCTAssertEqual(
            MenuBarRuntimeCommandPolicy.activationDecision(
                itemIdentifier: item.uniqueIdentifier,
                inventory: inventory,
                itemIsOnScreen: true
            ),
            .reject(.runtimeNotActionable(.waitForMenuBarVisibility))
        )
    }

    func testRuntimeCommandPolicyRejectsHiddenActivationWhenRuntimeCannotReveal() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 34,
            sourcePID: 1234,
            isOnScreen: false
        )
        var cache = MenuBarItemCache(displayID: 42)
        cache[.hidden] = [item]
        let failure = MenuBarRuntimeFailure(
            reason: .missingControlItems,
            detail: "hidden control item missing",
            occurredAt: Date(timeIntervalSince1970: 9)
        )
        let inventory = MenuBarRuntimeInventory(
            state: .degraded(failure),
            snapshot: MenuBarSnapshot(
                cache: cache,
                controlItemsMissing: true,
                systemMenuBarHidden: false
            )
        )

        XCTAssertEqual(
            MenuBarRuntimeCommandPolicy.activationDecision(
                itemIdentifier: item.uniqueIdentifier,
                inventory: inventory,
                itemIsOnScreen: false
            ),
            .reject(.runtimeNotActionable(.reacquireControlItems))
        )
    }

    func testRuntimeCommandPolicyRejectsHiddenActivationForLowConfidenceIdentity() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 35,
            sourcePID: nil,
            isOnScreen: false
        )
        var cache = MenuBarItemCache(displayID: 42)
        cache[.hidden] = [item]
        let inventory = MenuBarRuntimeInventory(
            state: .idle,
            snapshot: MenuBarSnapshot(
                cache: cache,
                controlItemsMissing: false,
                systemMenuBarHidden: false
            )
        )

        XCTAssertEqual(
            MenuBarRuntimeCommandPolicy.activationDecision(
                itemIdentifier: item.uniqueIdentifier,
                inventory: inventory,
                itemIsOnScreen: false
            ),
            .reject(.invalidIdentity(.titleOnly))
        )
    }

    func testRuntimeCommandPolicyFindsLiveCacheItemByExactIdentifier() {
        let target = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 36,
            sourcePID: 1234
        )
        let other = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.calendar", title: "Clock"),
            windowID: 37,
            sourcePID: 5678
        )
        var cache = MenuBarItemCache(displayID: 42)
        cache[.visible] = [other]
        cache[.hidden] = [target]

        XCTAssertEqual(
            MenuBarRuntimeCommandPolicy.liveItem(
                withIdentifier: target.uniqueIdentifier,
                in: cache
            ),
            target
        )
    }

    func testDiagnosticsEnterDegradedModeForMissingControlItems() {
        var diagnostics = MenuBarRuntimeDiagnostics()

        diagnostics.recordControlItemMiss(detail: "hidden control item missing")

        XCTAssertTrue(diagnostics.isDegraded)
        XCTAssertEqual(diagnostics.controlItemMisses, 1)
        XCTAssertEqual(diagnostics.lastFailure?.reason, .missingControlItems)
    }

    func testDiagnosticsReturnToIdleAfterActionableSnapshot() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 40,
            sourcePID: 1234
        )
        var cache = MenuBarItemCache(displayID: 84)
        cache[.visible] = [item]
        var diagnostics = MenuBarRuntimeDiagnostics()
        diagnostics.recordControlItemMiss(detail: "previous miss")

        diagnostics.recordSnapshot(
            MenuBarSnapshot(
                cache: cache,
                controlItemsMissing: false,
                systemMenuBarHidden: false,
                createdAt: Date(timeIntervalSince1970: 2)
            )
        )

        XCTAssertEqual(diagnostics.state, .idle)
        XCTAssertEqual(diagnostics.cacheCycles, 1)
        XCTAssertEqual(diagnostics.lastSnapshot?.itemCount, 1)
        XCTAssertEqual(diagnostics.unresolvedIdentityCount, 0)
    }

    func testDiagnosticsEnterDegradedModeForZeroItemSnapshot() {
        var diagnostics = MenuBarRuntimeDiagnostics()

        diagnostics.recordSnapshot(
            MenuBarSnapshot(
                cache: MenuBarItemCache(displayID: 84),
                controlItemsMissing: false,
                systemMenuBarHidden: false,
                createdAt: Date(timeIntervalSince1970: 2)
            ),
            zeroItemsDetail: "getMenuBarItems returned zero items after retry"
        )

        XCTAssertTrue(diagnostics.isDegraded)
        XCTAssertEqual(diagnostics.zeroItemSnapshots, 1)
        XCTAssertEqual(diagnostics.lastFailure?.reason, .zeroItems)
        XCTAssertEqual(diagnostics.lastSnapshot?.itemCount, 0)
    }

    func testDiagnosticsPreserveKnownGoodSnapshotForZeroItemObservation() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 41,
            sourcePID: 1234
        )
        var cache = MenuBarItemCache(displayID: 84)
        cache[.visible] = [item]
        var diagnostics = MenuBarRuntimeDiagnostics()

        diagnostics.recordZeroItemObservation(
            preserving: MenuBarSnapshot(
                cache: cache,
                controlItemsMissing: false,
                systemMenuBarHidden: false,
                createdAt: Date(timeIntervalSince1970: 2)
            ),
            detail: "getMenuBarItems returned zero items after retry"
        )

        XCTAssertTrue(diagnostics.isDegraded)
        XCTAssertEqual(diagnostics.zeroItemSnapshots, 1)
        XCTAssertEqual(diagnostics.lastFailure?.reason, .zeroItems)
        XCTAssertEqual(diagnostics.lastSnapshot?.itemCount, 1)
        XCTAssertEqual(diagnostics.lastSnapshot?.items.map(\.itemIdentifier), [item.uniqueIdentifier])
    }

    func testDiagnosticsRuntimeRecordsSnapshotFromCurrentHealthLatch() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 42,
            sourcePID: 1234
        )
        var cache = MenuBarItemCache(displayID: 84)
        cache[.visible] = [item]
        var runtime = MenuBarDiagnosticsRuntime()

        runtime.recordSnapshot(
            cache: cache,
            systemMenuBarHidden: false,
            createdAt: Date(timeIntervalSince1970: 3)
        )

        XCTAssertEqual(runtime.state, .idle)
        XCTAssertFalse(runtime.areControlItemsMissing)
        XCTAssertEqual(runtime.lastSnapshot?.itemCount, 1)
        XCTAssertEqual(runtime.lastSnapshot?.items.map(\.itemIdentifier), [item.uniqueIdentifier])
    }

    func testDiagnosticsRuntimeOwnsControlItemMissLatchAndSnapshot() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 43,
            sourcePID: 1234
        )
        var cache = MenuBarItemCache(displayID: 84)
        cache[.hidden] = [item]
        var runtime = MenuBarDiagnosticsRuntime()

        runtime.recordControlItemMiss(
            detail: "hidden control item missing",
            preserving: cache,
            systemMenuBarHidden: false
        )

        XCTAssertTrue(runtime.areControlItemsMissing)
        XCTAssertTrue(runtime.diagnostics.isDegraded)
        XCTAssertEqual(runtime.diagnostics.controlItemMisses, 1)
        XCTAssertEqual(runtime.diagnostics.lastFailure?.reason, .missingControlItems)
        XCTAssertEqual(runtime.lastSnapshot?.items.map(\.itemIdentifier), [item.uniqueIdentifier])
        XCTAssertEqual(runtime.lastSnapshot?.controlItemsMissing, true)

        runtime.markControlItemsAvailable()

        XCTAssertFalse(runtime.areControlItemsMissing)
    }

    func testDiagnosticsRuntimePreservesKnownGoodCacheOnZeroObservation() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 44,
            sourcePID: 1234
        )
        var cache = MenuBarItemCache(displayID: 84)
        cache[.hidden] = [item]
        var runtime = MenuBarDiagnosticsRuntime()

        runtime.recordZeroItemObservation(
            preserving: cache,
            systemMenuBarHidden: false,
            detail: "getMenuBarItems returned zero items after retry",
            createdAt: Date(timeIntervalSince1970: 4)
        )

        XCTAssertTrue(runtime.diagnostics.isDegraded)
        XCTAssertEqual(runtime.diagnostics.zeroItemSnapshots, 1)
        XCTAssertEqual(runtime.diagnostics.lastFailure?.reason, .zeroItems)
        XCTAssertEqual(runtime.lastSnapshot?.items.map(\.itemIdentifier), [item.uniqueIdentifier])
        XCTAssertFalse(runtime.lastSnapshot?.controlItemsMissing ?? true)
    }

    func testObservationRetryPolicyAcceptsNonEmptyObservation() {
        XCTAssertEqual(
            MenuBarObservationRetryPolicy.evaluate(
                observedItemCount: 1,
                attempt: 1
            ),
            .accept
        )
    }

    func testObservationRetryPolicyRetriesFirstZeroObservation() {
        XCTAssertEqual(
            MenuBarObservationRetryPolicy.evaluate(
                observedItemCount: 0,
                attempt: 1
            ),
            .retry(after: .milliseconds(250))
        )
    }

    func testObservationRetryPolicyFailsAfterRetryBudget() {
        XCTAssertEqual(
            MenuBarObservationRetryPolicy.evaluate(
                observedItemCount: 0,
                attempt: 2
            ),
            .fail(detail: "getMenuBarItems returned zero items after retry")
        )
    }

    func testInventoryExposesExactIdentifiersBySection() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 50,
            sourcePID: 1234
        )
        var cache = MenuBarItemCache(displayID: 126)
        cache[.hidden] = [item]
        let snapshot = MenuBarSnapshot(
            cache: cache,
            controlItemsMissing: false,
            systemMenuBarHidden: false,
            createdAt: Date(timeIntervalSince1970: 3)
        )

        let inventory = MenuBarRuntimeInventory(
            generatedAt: Date(timeIntervalSince1970: 4),
            state: .idle,
            snapshot: snapshot
        )

        XCTAssertTrue(inventory.isActionable)
        XCTAssertTrue(inventory.shownItems.isEmpty)
        XCTAssertEqual(inventory.hiddenItems.map(\.itemIdentifier), [item.uniqueIdentifier])
        XCTAssertEqual(inventory.item(withIdentifier: item.uniqueIdentifier)?.windowID, item.windowID)
    }

    func testInventoryIsNotActionableWhenRuntimeIsDegraded() {
        let snapshot = MenuBarSnapshot(
            displayID: 126,
            itemsBySection: [:],
            controlItemsMissing: true,
            systemMenuBarHidden: false
        )
        let failure = MenuBarRuntimeFailure(
            reason: .missingControlItems,
            detail: "hidden control item missing",
            occurredAt: Date(timeIntervalSince1970: 5)
        )

        let inventory = MenuBarRuntimeInventory(
            state: .degraded(failure),
            snapshot: snapshot
        )

        XCTAssertFalse(inventory.isActionable)
        XCTAssertTrue(inventory.isDegraded)
    }

    func testInventoryPreservesItemsWhileControlItemsAreMissing() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 51,
            sourcePID: 1234
        )
        var cache = MenuBarItemCache(displayID: 126)
        cache[.hidden] = [item]
        let failure = MenuBarRuntimeFailure(
            reason: .missingControlItems,
            detail: "hidden control item missing",
            occurredAt: Date(timeIntervalSince1970: 5)
        )
        let inventory = MenuBarRuntimeInventory(
            state: .degraded(failure),
            snapshot: MenuBarSnapshot(
                cache: cache,
                controlItemsMissing: true,
                systemMenuBarHidden: false
            )
        )

        XCTAssertFalse(inventory.isActionable)
        XCTAssertEqual(inventory.hiddenItems.map(\.itemIdentifier), [item.uniqueIdentifier])
        XCTAssertEqual(inventory.recommendedRecoveryAction, .reacquireControlItems)
    }

    func testRecoveryPolicyPreservesKnownGoodCacheAfterZeroItems() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 72,
            sourcePID: 1234
        )
        var cache = MenuBarItemCache(displayID: 126)
        cache[.hidden] = [item]
        let snapshot = MenuBarSnapshot(
            cache: cache,
            controlItemsMissing: false,
            systemMenuBarHidden: false
        )
        let failure = MenuBarRuntimeFailure(
            reason: .zeroItems,
            detail: "getMenuBarItems returned zero items after retry",
            occurredAt: Date(timeIntervalSince1970: 6)
        )
        let inventory = MenuBarRuntimeInventory(
            state: .degraded(failure),
            snapshot: snapshot
        )

        XCTAssertEqual(inventory.recommendedRecoveryAction, .preserveKnownGoodCache)
        XCTAssertEqual(inventory.hiddenItems.map(\.itemIdentifier), [item.uniqueIdentifier])
    }

    func testRecoveryPolicyReacquiresMissingControlItems() {
        let snapshot = MenuBarSnapshot(
            displayID: 126,
            itemsBySection: [:],
            controlItemsMissing: true,
            systemMenuBarHidden: false
        )
        let failure = MenuBarRuntimeFailure(
            reason: .missingControlItems,
            detail: "hidden control item missing",
            occurredAt: Date(timeIntervalSince1970: 7)
        )
        let inventory = MenuBarRuntimeInventory(
            state: .degraded(failure),
            snapshot: snapshot
        )

        XCTAssertEqual(inventory.recommendedRecoveryAction, .reacquireControlItems)
    }

    func testRecoveryPolicyRestoresBlockedItemsWhenRuntimeIsOtherwiseHealthy() {
        let blocked = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 70,
            bounds: CGRect(x: -1, y: 0, width: 24, height: 22),
            sourcePID: 1234
        )
        var cache = MenuBarItemCache(displayID: 126)
        cache[.hidden] = [blocked]
        let inventory = MenuBarRuntimeInventory(
            state: .idle,
            snapshot: MenuBarSnapshot(
                cache: cache,
                controlItemsMissing: false,
                systemMenuBarHidden: false
            )
        )

        XCTAssertEqual(inventory.snapshot.blockedItems.map(\.itemIdentifier), [blocked.uniqueIdentifier])
        XCTAssertEqual(inventory.recommendedRecoveryAction, .restoreBlockedItemsToVisible)
    }

    func testRecoveryPolicyReturnsNoneForHealthyInventory() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 71,
            sourcePID: 1234
        )
        var cache = MenuBarItemCache(displayID: 126)
        cache[.visible] = [item]
        let inventory = MenuBarRuntimeInventory(
            state: .idle,
            snapshot: MenuBarSnapshot(
                cache: cache,
                controlItemsMissing: false,
                systemMenuBarHidden: false
            )
        )

        XCTAssertEqual(inventory.recommendedRecoveryAction, .none)
    }

    func testNotchBudgetSubtractsPersistentNonLayoutAndChevronFootprints() {
        let chevron = "continuum:VisibleControlItem"
        let visible = "com.example.visible:Status"
        let hiddenControl = "continuum:HiddenControlItem"
        let items = [
            notchBudgetItem(
                chevron,
                tag: .visibleControlItem,
                x: 870,
                width: 20,
                isLayoutItem: true
            ),
            notchBudgetItem(
                visible,
                tag: .appItem(bundleID: "com.example.visible", title: "Status"),
                x: 830,
                width: 24,
                isLayoutItem: true
            ),
            notchBudgetItem("clock", tag: .clock, x: 760, width: 30),
            notchBudgetItem("audio", tag: .audioVideoModule, x: 720, width: 99),
            notchBudgetItem(
                "live-activity",
                tag: MenuBarItemTag(namespace: .controlCenter, title: "Item-0"),
                x: 700,
                width: 80,
                isTransient: true
            ),
            notchBudgetItem("outside", tag: .clock, x: 450, width: 40),
        ]

        let budget = MenuBarNotchBudgetPolicy.buildBudget(
            items: items,
            desiredFiltered: [chevron, visible, "missing", hiddenControl],
            hiddenControlUID: hiddenControl,
            visibleControlUID: chevron,
            controlCenterBounds: CGRect(x: 900, y: 0, width: 40, height: 22),
            screenMaxX: 1_000,
            notchMaxX: 500,
            notchGap: 12
        )

        XCTAssertEqual(budget.rightBoundary, 900)
        XCTAssertEqual(budget.availableWidth, 338)
        XCTAssertEqual(budget.visibleUIDs, [chevron, visible, "missing"])
        XCTAssertEqual(budget.uidWidths[chevron], 20)
        XCTAssertEqual(budget.uidWidths[visible], 24)
        XCTAssertNil(budget.uidWidths["missing"])
        XCTAssertEqual(budget.nonLayoutCount, 1)
        XCTAssertEqual(budget.nonLayoutFootprint, 30)
        XCTAssertEqual(budget.chevronFootprint, 20)
        XCTAssertTrue(budget.nonLayoutBreakdown.contains { $0.hasPrefix("clock=") })
    }

    func testNotchBudgetUsesScreenBoundaryWhenControlCenterIsMissing() {
        let budget = MenuBarNotchBudgetPolicy.buildBudget(
            items: [],
            desiredFiltered: [],
            hiddenControlUID: "hidden",
            visibleControlUID: nil,
            controlCenterBounds: nil,
            screenMaxX: 1_000,
            notchMaxX: 600,
            notchGap: 10
        )

        XCTAssertEqual(budget.rightBoundary, 1_000)
        XCTAssertEqual(budget.availableWidth, 390)
        XCTAssertTrue(budget.visibleUIDs.isEmpty)
        XCTAssertTrue(budget.uidWidths.isEmpty)
    }

    func testNotchBudgetExcludesTransientIndicatorsFromFootprint() {
        let transientItems = [
            notchBudgetItem("audio", tag: .audioVideoModule, x: 760, width: 20),
            notchBudgetItem("facetime", tag: .faceTime, x: 780, width: 22),
            notchBudgetItem("capture", tag: .screenCaptureUI, x: 804, width: 24),
            notchBudgetItem("game", tag: .gameMode, x: 830, width: 26),
            notchBudgetItem(
                "live-activity",
                tag: MenuBarItemTag(namespace: .controlCenter, title: "Item-9"),
                x: 860,
                width: 28,
                isTransient: true
            ),
        ]

        let budget = MenuBarNotchBudgetPolicy.buildBudget(
            items: transientItems,
            desiredFiltered: [],
            hiddenControlUID: "hidden",
            visibleControlUID: nil,
            controlCenterBounds: CGRect(x: 920, y: 0, width: 40, height: 22),
            screenMaxX: 1_000,
            notchMaxX: 700,
            notchGap: 10
        )

        XCTAssertEqual(budget.availableWidth, 210)
        XCTAssertEqual(budget.nonLayoutCount, 0)
        XCTAssertEqual(budget.nonLayoutFootprint, 0)
        XCTAssertTrue(budget.nonLayoutBreakdown.isEmpty)
    }

    func testUnmanagedPlacementPolicyExcludesUnresolvedControlCenterGenericItems() {
        let visibleControl = "continuum:VisibleControlItem"
        let hiddenControl = "continuum:HiddenControlItem"
        let alwaysHiddenControl = "continuum:AlwaysHiddenControlItem"
        let savedUID = "com.example.saved:Status"
        let newUID = "com.example.new:Status"
        let unresolvedUID = "com.apple.controlcenter:Item-0"

        let plan = MenuBarUnmanagedPlacementPolicy.plan(
            items: [
                unmanagedPlacementItem(visibleControl, tag: .visibleControlItem, sourcePID: nil),
                unmanagedPlacementItem(
                    newUID,
                    tag: .appItem(bundleID: "com.example.new", title: "Status")
                ),
                unmanagedPlacementItem(
                    unresolvedUID,
                    tag: MenuBarItemTag(namespace: .controlCenter, title: "Item-0"),
                    sourcePID: nil
                ),
            ],
            currentFlat: [visibleControl, savedUID, newUID, unresolvedUID, hiddenControl, alwaysHiddenControl],
            desiredFiltered: [savedUID, hiddenControl, alwaysHiddenControl],
            sectionMap: [
                savedUID: "visible",
                hiddenControl: "hidden",
                alwaysHiddenControl: "alwaysHidden",
            ],
            savedSectionOrder: ["visible": [savedUID]],
            newItemsPlacement: newItemsPlacement(section: "hidden"),
            hiddenControlUID: hiddenControl,
            alwaysHiddenControlUID: alwaysHiddenControl
        )

        XCTAssertEqual(plan.visibleControlUID, visibleControl)
        XCTAssertEqual(plan.unresolvedGenericControlCenterUIDs, [unresolvedUID])
        XCTAssertEqual(plan.unmanagedUIDs, [newUID])
        XCTAssertEqual(plan.placements[newUID], .newItemDefault(section: .hidden))
        XCTAssertEqual(
            plan.desiredFiltered,
            [savedUID, hiddenControl, newUID, alwaysHiddenControl]
        )
        XCTAssertEqual(plan.sectionMap[newUID], "hidden")
    }

    func testUnmanagedPlacementPolicyRestoresSavedBaseIdentifierPosition() {
        let hiddenControl = "continuum:HiddenControlItem"
        let staleSavedUID = "com.example.known:Status:1"
        let currentUID = "com.example.known:Status:2"
        let neighborUID = "com.example.neighbor:Status"

        let plan = MenuBarUnmanagedPlacementPolicy.plan(
            items: [
                unmanagedPlacementItem(
                    currentUID,
                    tag: .appItem(
                        bundleID: "com.example.known",
                        title: "Status",
                        instanceIndex: 2
                    )
                ),
                unmanagedPlacementItem(
                    neighborUID,
                    tag: .appItem(bundleID: "com.example.neighbor", title: "Status")
                ),
            ],
            currentFlat: [currentUID, neighborUID, hiddenControl],
            desiredFiltered: [neighborUID, hiddenControl],
            sectionMap: [
                neighborUID: "visible",
                hiddenControl: "hidden",
            ],
            savedSectionOrder: ["visible": [staleSavedUID, neighborUID]],
            newItemsPlacement: newItemsPlacement(section: "hidden"),
            hiddenControlUID: hiddenControl,
            alwaysHiddenControlUID: nil
        )

        XCTAssertEqual(plan.unmanagedUIDs, [currentUID])
        XCTAssertEqual(plan.placements[currentUID], .saved(section: .visible, index: 0))
        XCTAssertEqual(plan.desiredFiltered, [currentUID, neighborUID, hiddenControl])
        XCTAssertEqual(plan.sectionMap[currentUID], "visible")
        XCTAssertEqual(plan.placementSummary(for: currentUID), "saved(section=visible section, index=0)")
    }

    func testMoveCommandNormalizesAttemptsAndMapsRelation() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 80,
            sourcePID: 1234
        )
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 81,
            sourcePID: 1235
        )

        let leftCommand = MenuBarMoveCommand(
            item: item,
            destination: .leftOfItem(anchor),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 0
        )
        let rightCommand = MenuBarMoveCommand(
            item: item,
            destination: .rightOfItem(anchor),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 3
        )

        XCTAssertEqual(leftCommand.normalizedMaxAttempts, 1)
        XCTAssertEqual(leftCommand.relation, .leftOfItem)
        XCTAssertEqual(rightCommand.normalizedMaxAttempts, 3)
        XCTAssertEqual(rightCommand.relation, .rightOfItem)
    }

    func testMoveCommandUsesPreflightPolicy() {
        let item = MenuBarItem.fixture(
            tag: MenuBarItemTag(
                namespace: .controlCenter,
                title: "Item-0",
                windowID: 82
            ),
            windowID: 82,
            sourcePID: nil,
            ownerPID: 999,
            title: "Item-0"
        )
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 83,
            sourcePID: 1235
        )
        let command = MenuBarMoveCommand(
            item: item,
            destination: .leftOfItem(anchor),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 8
        )

        XCTAssertEqual(command.preflight(isBlocked: false), .reject(.invalidIdentity(.unresolved)))
    }

    func testMoveCommandControlsRetryBoundaries() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 84,
            sourcePID: 1234
        )
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 85,
            sourcePID: 1235
        )
        let command = MenuBarMoveCommand(
            item: item,
            destination: .rightOfItem(anchor),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 2
        )

        XCTAssertTrue(command.shouldRetry(afterAttempt: 1))
        XCTAssertFalse(command.shouldRetry(afterAttempt: 2))
    }

    func testDisplayResolutionPolicyResolvesMoveDisplayByFallbackPriority() {
        XCTAssertEqual(
            MenuBarDisplayResolutionPolicy.moveDisplayID(
                explicitDisplayID: 10,
                bestScreenDisplayID: 20,
                activeMenuBarDisplayID: 30,
                mainDisplayID: 40
            ),
            10
        )
        XCTAssertEqual(
            MenuBarDisplayResolutionPolicy.moveDisplayID(
                explicitDisplayID: nil,
                bestScreenDisplayID: 20,
                activeMenuBarDisplayID: 30,
                mainDisplayID: 40
            ),
            20
        )
        XCTAssertEqual(
            MenuBarDisplayResolutionPolicy.moveDisplayID(
                explicitDisplayID: nil,
                bestScreenDisplayID: nil,
                activeMenuBarDisplayID: 30,
                mainDisplayID: 40
            ),
            30
        )
        XCTAssertEqual(
            MenuBarDisplayResolutionPolicy.moveDisplayID(
                explicitDisplayID: nil,
                bestScreenDisplayID: nil,
                activeMenuBarDisplayID: nil,
                mainDisplayID: 40
            ),
            40
        )
    }

    func testDisplayResolutionPolicyUsesItemScreenForTemporaryReveal() {
        let screens = [
            MenuBarDisplayResolutionPolicy.ScreenObservation(
                displayID: 100,
                frame: CGRect(x: 0, y: 0, width: 1_000, height: 900)
            ),
            MenuBarDisplayResolutionPolicy.ScreenObservation(
                displayID: 200,
                frame: CGRect(x: 1_000, y: 0, width: 1_000, height: 900)
            ),
        ]

        XCTAssertEqual(
            MenuBarDisplayResolutionPolicy.temporaryRevealDisplayID(
                explicitDisplayID: nil,
                itemBounds: CGRect(x: 1_050, y: 20, width: 24, height: 22),
                screens: screens,
                activeMenuBarDisplayID: 300,
                mainDisplayID: 400
            ),
            200
        )
    }

    func testDisplayResolutionPolicyTemporaryRevealFallbacksAreStable() {
        let screens = [
            MenuBarDisplayResolutionPolicy.ScreenObservation(
                displayID: 100,
                frame: CGRect(x: 0, y: 0, width: 1_000, height: 900)
            ),
        ]

        XCTAssertEqual(
            MenuBarDisplayResolutionPolicy.temporaryRevealDisplayID(
                explicitDisplayID: 50,
                itemBounds: CGRect(x: 1_050, y: 20, width: 24, height: 22),
                screens: screens,
                activeMenuBarDisplayID: 300,
                mainDisplayID: 400
            ),
            50
        )
        XCTAssertEqual(
            MenuBarDisplayResolutionPolicy.temporaryRevealDisplayID(
                explicitDisplayID: nil,
                itemBounds: CGRect(x: 1_050, y: 20, width: 24, height: 22),
                screens: screens,
                activeMenuBarDisplayID: 300,
                mainDisplayID: 400
            ),
            300
        )
        XCTAssertEqual(
            MenuBarDisplayResolutionPolicy.temporaryRevealDisplayID(
                explicitDisplayID: nil,
                itemBounds: CGRect(x: 1_050, y: 20, width: 24, height: 22),
                screens: screens,
                activeMenuBarDisplayID: nil,
                mainDisplayID: 400
            ),
            400
        )
    }

    func testMoveGeometryPolicyBuildsTargetPointsFromDestinationSide() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 120,
            sourcePID: 1234
        )
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 121,
            sourcePID: 1235
        )
        let targetBounds = CGRect(x: 100, y: 20, width: 30, height: 22)

        XCTAssertEqual(
            MenuBarMoveGeometryPolicy.eventPoints(
                for: .leftOfItem(anchor),
                targetBounds: targetBounds
            ),
            .init(start: CGPoint(x: 100, y: 20), end: CGPoint(x: 100, y: 20))
        )
        XCTAssertEqual(
            MenuBarMoveGeometryPolicy.eventPoints(
                for: .rightOfItem(item),
                targetBounds: targetBounds
            ),
            .init(start: CGPoint(x: 130, y: 20), end: CGPoint(x: 130, y: 20))
        )
    }

    func testMoveGeometryPolicySkipsWarpWhenTargetPointIsOffscreen() {
        let screenFrames = [
            CGRect(x: 0, y: 0, width: 1_440, height: 900),
            CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
        ]

        XCTAssertEqual(
            MenuBarMoveGeometryPolicy.cursorWarpDecision(
                warpPoint: CGPoint(x: 100, y: 20),
                screenFrames: screenFrames
            ),
            .warpAndSettle
        )
        XCTAssertEqual(
            MenuBarMoveGeometryPolicy.cursorWarpDecision(
                warpPoint: CGPoint(x: -4_000, y: 20),
                screenFrames: screenFrames
            ),
            .skipWarp
        )
    }

    func testMoveGeometryPolicyRedirectsOffscreenMouseDownIntoActiveNotch() {
        let original = CGPoint(x: -4_000, y: 20)
        let notchFrame = CGRect(x: 670, y: 860, width: 100, height: 40)

        XCTAssertEqual(
            MenuBarMoveGeometryPolicy.mouseDownLocation(
                originalLocation: original,
                warpDecision: .skipWarp,
                activeScreenNotchFrame: notchFrame
            ),
            CGPoint(x: 720, y: 880)
        )
        XCTAssertEqual(
            MenuBarMoveGeometryPolicy.mouseDownLocation(
                originalLocation: original,
                warpDecision: .skipWarp,
                activeScreenNotchFrame: nil
            ),
            original
        )
        XCTAssertEqual(
            MenuBarMoveGeometryPolicy.mouseDownLocation(
                originalLocation: original,
                warpDecision: .warpAndSettle,
                activeScreenNotchFrame: notchFrame
            ),
            original
        )
    }

    func testMoveCommandPositionMatchPolicyKeepsControlItemRetriesHonest() {
        let control = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 86,
            sourcePID: nil
        )
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 87,
            sourcePID: 1234
        )
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 88,
            sourcePID: 1235
        )
        let controlCommand = MenuBarMoveCommand(
            item: control,
            destination: .rightOfItem(anchor),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 8
        )
        let appCommand = MenuBarMoveCommand(
            item: appItem,
            destination: .rightOfItem(anchor),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 8
        )

        XCTAssertTrue(controlCommand.acceptsPositionMatch(atAttempt: 1, observedDisplacement: false))
        XCTAssertFalse(controlCommand.acceptsPositionMatch(atAttempt: 2, observedDisplacement: false))
        XCTAssertTrue(controlCommand.acceptsPositionMatch(atAttempt: 2, observedDisplacement: true))
        XCTAssertTrue(appCommand.acceptsPositionMatch(atAttempt: 2, observedDisplacement: false))
    }

    func testMoveExecutionTracksAttemptsAndDisplacement() {
        let control = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 100,
            sourcePID: nil
        )
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 101,
            sourcePID: 1235
        )
        let command = MenuBarMoveCommand(
            item: control,
            destination: .rightOfItem(anchor),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 2
        )
        var execution = MenuBarMoveExecution(command: command)

        XCTAssertEqual(execution.maxAttempts, 2)
        XCTAssertFalse(execution.acceptsCurrentPositionMatch())
        XCTAssertFalse(execution.shouldRetryCurrentAttempt())
        XCTAssertEqual(execution.beginAttempt(), 1)
        XCTAssertTrue(execution.acceptsCurrentPositionMatch())
        XCTAssertTrue(execution.shouldRetryCurrentAttempt())
        XCTAssertEqual(execution.beginAttempt(), 2)
        XCTAssertFalse(execution.acceptsCurrentPositionMatch())
        XCTAssertFalse(execution.shouldRetryCurrentAttempt())

        execution.recordObservedDisplacement()

        XCTAssertTrue(execution.acceptsCurrentPositionMatch())
        XCTAssertNil(execution.beginAttempt())
    }

    func testMoveExecutionNamesPositionMatchAndRetryDecisions() {
        let control = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 104,
            sourcePID: nil
        )
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 105,
            sourcePID: 1235
        )
        let command = MenuBarMoveCommand(
            item: control,
            destination: .rightOfItem(anchor),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 2
        )
        var execution = MenuBarMoveExecution(command: command)

        XCTAssertEqual(execution.beginAttempt(), 1)
        XCTAssertEqual(execution.positionMatchDecision(), .accept)
        XCTAssertEqual(execution.continuationAfterUnverifiedAttempt(), .retry)
        XCTAssertEqual(execution.continuationAfterFailedAttempt(), .retry)
        XCTAssertEqual(execution.beginAttempt(), 2)
        XCTAssertEqual(execution.positionMatchDecision(), .retryAsPossibleFalsePositive)
        XCTAssertEqual(execution.continuationAfterUnverifiedAttempt(), .stop)
        XCTAssertEqual(execution.continuationAfterFailedAttempt(), .stop)

        execution.recordObservedDisplacement()

        XCTAssertEqual(execution.positionMatchDecision(), .accept)
    }

    func testMoveExecutionDiagnosticsIncludeAttemptBudgetAndDisplacement() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 106,
            sourcePID: 1234
        )
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 107,
            sourcePID: 1235
        )
        let command = MenuBarMoveCommand(
            item: item,
            destination: .leftOfItem(anchor),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 2
        )
        var execution = MenuBarMoveExecution(command: command)
        _ = execution.beginAttempt()
        _ = execution.beginAttempt()
        execution.recordObservedDisplacement()

        XCTAssertTrue(execution.failedAttemptDetail(error: CancellationError()).contains("attempt=2/2"))
        XCTAssertTrue(execution.exhaustedAttemptsDetail().contains("displaced=true"))
    }

    @MainActor
    func testMoveSessionExecutorRunsVerifiedMoveWithStableCursorAndHIDLifetime() async throws {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 108,
            sourcePID: 1234
        )
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 109,
            sourcePID: 1235
        )
        let command = MenuBarMoveCommand(
            item: item,
            destination: .leftOfItem(anchor),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 2
        )
        var positionResults = [false, false, true]
        var events = [String]()

        let outcome = try await MenuBarMoveSessionExecutor.execute(
            command: command,
            itemIsBlocked: false,
            resolvedDisplayID: 7,
            operations: MenuBarMoveSessionExecutor.Operations(
                taskIsCancelled: { false },
                waitForUserToPauseInput: {
                    events.append("wait-input")
                },
                stopHIDEvents: {
                    events.append("stop-hid")
                },
                startHIDEvents: {
                    events.append("start-hid")
                },
                waitForMoveOperationBuffer: {
                    events.append("buffer")
                },
                itemHasCorrectPosition: { _, _ in
                    let result = positionResults.removeFirst()
                    events.append("position:\(result)")
                    return result
                },
                shouldManageCursor: { true },
                mouseLocation: {
                    events.append("mouse")
                    return CGPoint(x: 20, y: 30)
                },
                hideCursor: { _ in
                    events.append("hide")
                },
                warpCursor: { point in
                    events.append("warp:\(Int(point.x))")
                },
                showCursor: {
                    events.append("show")
                },
                postMoveEvents: { _, _ in
                    events.append("post")
                },
                validateItemPositionAfterMove: { _, _ in
                    events.append("validate")
                },
                recordOperationFailure: { detail in
                    XCTFail("Unexpected operation failure: \(detail)")
                }
            ),
            diagnostics: MenuBarMoveSessionExecutor.Diagnostics(
                recordMoveStart: { _, displayID in
                    events.append("start:\(displayID)")
                },
                recordAttemptVerified: { attempt in
                    events.append("verified:\(attempt)")
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarMoveSessionExecutor.Outcome(
                attempts: 1,
                observedDisplacement: true,
                stopReason: .verifiedAfterEvents
            )
        )
        XCTAssertEqual(
            events,
            [
                "wait-input",
                "stop-hid",
                "buffer",
                "start:7",
                "position:false",
                "mouse",
                "hide",
                "position:false",
                "post",
                "position:true",
                "verified:1",
                "validate",
                "warp:20",
                "show",
                "start-hid",
            ]
        )
    }

    @MainActor
    func testMoveSessionExecutorRetriesAfterFailedAttemptThenVerifies() async throws {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.retry", title: "Retry"),
            windowID: 110,
            sourcePID: 1234
        )
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 111,
            sourcePID: 1235
        )
        let command = MenuBarMoveCommand(
            item: item,
            destination: .rightOfItem(anchor),
            displayID: nil,
            skipInputPause: true,
            watchdogTimeout: nil,
            maxMoveAttempts: 2
        )
        var positionResults = [false, false, false, true]
        var postAttempts = 0
        var events = [String]()

        let outcome = try await MenuBarMoveSessionExecutor.execute(
            command: command,
            itemIsBlocked: false,
            resolvedDisplayID: 8,
            operations: MenuBarMoveSessionExecutor.Operations(
                taskIsCancelled: { false },
                waitForUserToPauseInput: {
                    XCTFail("Input pause should be skipped")
                },
                stopHIDEvents: {
                    events.append("stop-hid")
                },
                startHIDEvents: {
                    events.append("start-hid")
                },
                waitForMoveOperationBuffer: {
                    events.append("buffer")
                },
                itemHasCorrectPosition: { _, _ in
                    let result = positionResults.removeFirst()
                    events.append("position:\(result)")
                    return result
                },
                shouldManageCursor: { false },
                mouseLocation: {
                    XCTFail("Mouse location should not be read when cursor is externally managed")
                    return .zero
                },
                hideCursor: { _ in
                    XCTFail("Cursor should not be hidden when externally managed")
                },
                warpCursor: { _ in
                    XCTFail("Cursor should not be warped when externally managed")
                },
                showCursor: {
                    XCTFail("Cursor should not be shown when externally managed")
                },
                postMoveEvents: { _, _ in
                    postAttempts += 1
                    events.append("post:\(postAttempts)")
                    if postAttempts == 1 {
                        throw CancellationError()
                    }
                },
                validateItemPositionAfterMove: { _, _ in
                    events.append("validate")
                },
                recordOperationFailure: { detail in
                    XCTFail("Unexpected operation failure: \(detail)")
                }
            ),
            diagnostics: MenuBarMoveSessionExecutor.Diagnostics(
                recordAttemptVerified: { attempt in
                    events.append("verified:\(attempt)")
                },
                recordAttemptFailed: { attempt, _ in
                    events.append("failed:\(attempt)")
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarMoveSessionExecutor.Outcome(
                attempts: 2,
                observedDisplacement: true,
                stopReason: .verifiedAfterEvents
            )
        )
        XCTAssertEqual(
            events,
            [
                "stop-hid",
                "buffer",
                "position:false",
                "position:false",
                "post:1",
                "failed:1",
                "buffer",
                "position:false",
                "post:2",
                "position:true",
                "verified:2",
                "validate",
                "start-hid",
            ]
        )
    }

    @MainActor
    func testMoveSessionExecutorStopsBeforeLiveOperationsForSystemCloneNoOp() async throws {
        let clone = MenuBarItem.fixture(
            tag: .appItem(
                bundleID: "com.example.clone",
                title: "System Status Item Clone",
                windowID: 112
            ),
            windowID: 112,
            sourcePID: nil,
            title: "System Status Item Clone"
        )
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 113,
            sourcePID: 1235
        )
        let command = MenuBarMoveCommand(
            item: clone,
            destination: .leftOfItem(anchor),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 2
        )
        var events = [String]()

        let outcome = try await MenuBarMoveSessionExecutor.execute(
            command: command,
            itemIsBlocked: false,
            resolvedDisplayID: 9,
            operations: MenuBarMoveSessionExecutor.Operations(
                taskIsCancelled: { false },
                waitForUserToPauseInput: {
                    XCTFail("Input pause should not run for a no-op preflight")
                },
                stopHIDEvents: {
                    XCTFail("HID should not stop for a no-op preflight")
                },
                startHIDEvents: {
                    XCTFail("HID should not start for a no-op preflight")
                },
                waitForMoveOperationBuffer: {
                    XCTFail("Move buffer should not run for a no-op preflight")
                },
                itemHasCorrectPosition: { _, _ in
                    XCTFail("Position check should not run for a no-op preflight")
                    return false
                },
                shouldManageCursor: { false },
                mouseLocation: { .zero },
                hideCursor: { _ in },
                warpCursor: { _ in },
                showCursor: {},
                postMoveEvents: { _, _ in
                    XCTFail("Move events should not post for a no-op preflight")
                },
                validateItemPositionAfterMove: { _, _ in
                    XCTFail("Validation should not run for a no-op preflight")
                },
                recordOperationFailure: { detail in
                    XCTFail("No-op preflight should not record failure: \(detail)")
                }
            ),
            diagnostics: MenuBarMoveSessionExecutor.Diagnostics(
                recordNoOp: { _, reason in
                    events.append("noop:\(reason)")
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarMoveSessionExecutor.Outcome(
                attempts: 0,
                observedDisplacement: false,
                stopReason: .noOp(.systemClone)
            )
        )
        XCTAssertEqual(events, ["noop:systemClone"])
    }

    @MainActor
    func testMoveSessionExecutorValidatesAndRecordsFailureWhenAttemptsExhaust() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.exhaust", title: "Exhaust"),
            windowID: 114,
            sourcePID: 1234
        )
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 115,
            sourcePID: 1235
        )
        let command = MenuBarMoveCommand(
            item: item,
            destination: .rightOfItem(anchor),
            displayID: nil,
            skipInputPause: true,
            watchdogTimeout: nil,
            maxMoveAttempts: 1
        )
        var positionResults = [false, false, false]
        var events = [String]()
        var recordedFailures = [String]()

        do {
            _ = try await MenuBarMoveSessionExecutor.execute(
                command: command,
                itemIsBlocked: false,
                resolvedDisplayID: 10,
                operations: MenuBarMoveSessionExecutor.Operations(
                    taskIsCancelled: { false },
                    waitForUserToPauseInput: {},
                    stopHIDEvents: {
                        events.append("stop-hid")
                    },
                    startHIDEvents: {
                        events.append("start-hid")
                    },
                    waitForMoveOperationBuffer: {
                        events.append("buffer")
                    },
                    itemHasCorrectPosition: { _, _ in
                        let result = positionResults.removeFirst()
                        events.append("position:\(result)")
                        return result
                    },
                    shouldManageCursor: { false },
                    mouseLocation: { .zero },
                    hideCursor: { _ in },
                    warpCursor: { _ in },
                    showCursor: {},
                    postMoveEvents: { _, _ in
                        events.append("post")
                    },
                    validateItemPositionAfterMove: { _, _ in
                        events.append("validate")
                    },
                    recordOperationFailure: { detail in
                        recordedFailures.append(detail)
                        events.append("record-failure")
                    }
                ),
                diagnostics: MenuBarMoveSessionExecutor.Diagnostics(
                    recordAttemptUnverified: { attempt in
                        events.append("unverified:\(attempt)")
                    },
                    recordAttemptsExhausted: { execution in
                        events.append("exhausted:\(execution.maxAttempts)")
                    }
                )
            )
            XCTFail("Expected exhausted move attempts to throw")
        } catch MenuBarEventError.cannotComplete {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(
            events,
            [
                "stop-hid",
                "buffer",
                "position:false",
                "position:false",
                "post",
                "position:false",
                "unverified:1",
                "validate",
                "record-failure",
                "exhausted:1",
                "start-hid",
            ]
        )
        XCTAssertEqual(recordedFailures.count, 1)
        XCTAssertTrue(recordedFailures.first?.contains("Move exhausted 1 attempt(s)") == true)
    }

    func testClickExecutionNormalizesAttemptsAndStopsAfterBudget() {
        var execution = MenuBarClickExecution(maxAttempts: 0)

        XCTAssertEqual(execution.maxAttempts, 1)
        XCTAssertEqual(execution.beginAttempt(), 1)
        XCTAssertEqual(execution.continuationAfterFailedAttempt(), .stop)
        XCTAssertNil(execution.beginAttempt())
    }

    func testClickExecutionRetriesUntilLastAttempt() {
        var execution = MenuBarClickExecution(maxAttempts: 3)

        XCTAssertEqual(execution.beginAttempt(), 1)
        XCTAssertEqual(execution.continuationAfterFailedAttempt(), .retry)
        XCTAssertEqual(execution.beginAttempt(), 2)
        XCTAssertEqual(execution.continuationAfterFailedAttempt(), .retry)
        XCTAssertEqual(execution.beginAttempt(), 3)
        XCTAssertEqual(execution.continuationAfterFailedAttempt(), .stop)
        XCTAssertNil(execution.beginAttempt())
    }

    @MainActor
    func testClickExecutorRunsInputAndHIDSessionAroundSuccessfulClick() async throws {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.click", title: "Click"),
            windowID: 1_440
        )
        var events = [String]()
        var posted = [(MenuBarItem, CGMouseButton)]()

        let outcome = try await MenuBarClickExecutor.execute(
            item: item,
            mouseButton: .left,
            skipInputPause: false,
            maxAttempts: 3,
            waitForUserToPauseInput: {
                events.append("wait")
            },
            beginInputSession: {
                events.append("begin")
            },
            endInputSession: {
                events.append("end")
            },
            postClickEvents: { item, mouseButton in
                events.append("post")
                posted.append((item, mouseButton))
            },
            sleepAfterFailedAttempt: {
                events.append("sleep")
            },
            now: { Date(timeIntervalSince1970: 0) },
            recordClickStart: { _, _ in
                events.append("start")
            },
            recordAttemptSuccess: { attempt, _ in
                events.append("success-\(attempt)")
            },
            recordAttemptFailure: { attempt, _, _ in
                events.append("failure-\(attempt)")
            }
        )

        XCTAssertEqual(outcome, MenuBarClickExecutor.Outcome(attemptCount: 1))
        XCTAssertEqual(events, ["wait", "start", "begin", "post", "success-1", "end"])
        XCTAssertEqual(posted.count, 1)
        XCTAssertEqual(posted.first?.0, item)
        XCTAssertEqual(posted.first?.1, .left)
    }

    @MainActor
    func testClickExecutorRetriesAfterMenuBarEventFailure() async throws {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.retry-click", title: "RetryClick"),
            windowID: 1_450
        )
        var events = [String]()
        var postAttempts = 0

        let outcome = try await MenuBarClickExecutor.execute(
            item: item,
            mouseButton: .right,
            skipInputPause: true,
            maxAttempts: 2,
            waitForUserToPauseInput: {
                events.append("wait")
            },
            beginInputSession: {
                events.append("begin")
            },
            endInputSession: {
                events.append("end")
            },
            postClickEvents: { _, _ in
                postAttempts += 1
                events.append("post-\(postAttempts)")
                if postAttempts == 1 {
                    throw MenuBarEventError.cannotComplete
                }
            },
            sleepAfterFailedAttempt: {
                events.append("sleep")
            },
            now: { Date(timeIntervalSince1970: TimeInterval(postAttempts)) },
            recordAttemptSuccess: { attempt, _ in
                events.append("success-\(attempt)")
            },
            recordAttemptFailure: { attempt, _, _ in
                events.append("failure-\(attempt)")
            }
        )

        XCTAssertEqual(outcome, MenuBarClickExecutor.Outcome(attemptCount: 2))
        XCTAssertEqual(
            events,
            ["begin", "post-1", "failure-1", "sleep", "post-2", "success-2", "end"]
        )
    }

    @MainActor
    func testClickExecutorMapsUnknownFailureAndEndsHIDSession() async {
        struct UnknownClickError: Error {}

        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.unknown-click", title: "UnknownClick"),
            windowID: 1_460
        )
        var events = [String]()

        do {
            _ = try await MenuBarClickExecutor.execute(
                item: item,
                mouseButton: .left,
                skipInputPause: true,
                maxAttempts: 1,
                waitForUserToPauseInput: {
                    events.append("wait")
                },
                beginInputSession: {
                    events.append("begin")
                },
                endInputSession: {
                    events.append("end")
                },
                postClickEvents: { _, _ in
                    events.append("post")
                    throw UnknownClickError()
                },
                sleepAfterFailedAttempt: {
                    events.append("sleep")
                },
                recordAttemptFailure: { attempt, _, _ in
                    events.append("failure-\(attempt)")
                }
            )
            XCTFail("Expected unknown click error to be normalized")
        } catch let error as MenuBarEventError {
            XCTAssertEqual(
                error.description,
                MenuBarEventError.cannotComplete.description
            )
        } catch {
            XCTFail("Expected MenuBarEventError.cannotComplete, got \(error)")
        }

        XCTAssertEqual(events, ["begin", "post", "failure-1", "end"])
    }

    func testClickTargetPolicyRoutesOffscreenItemsThroughTemporaryReveal() {
        XCTAssertEqual(
            MenuBarClickTargetPolicy.activationRoute(itemIsOnScreen: true),
            .clickInPlace
        )
        XCTAssertEqual(
            MenuBarClickTargetPolicy.activationRoute(itemIsOnScreen: false),
            .temporarilyReveal
        )
    }

    func testClickTargetPolicyAttemptsAccessibilityPressOnlyForLeftClickElectronItems() {
        XCTAssertTrue(
            MenuBarClickTargetPolicy.shouldAttemptAccessibilityPress(
                mouseButton: .left,
                isElectronItem: true
            )
        )
        XCTAssertFalse(
            MenuBarClickTargetPolicy.shouldAttemptAccessibilityPress(
                mouseButton: .right,
                isElectronItem: true
            )
        )
        XCTAssertFalse(
            MenuBarClickTargetPolicy.shouldAttemptAccessibilityPress(
                mouseButton: .left,
                isElectronItem: false
            )
        )
    }

    func testClickTargetPolicyPrefersExactWindowWhenRefreshingTarget() {
        let stale = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status", title: "Status", windowID: 130),
            windowID: 130,
            sourcePID: 5_001
        )
        let sameIdentityNewWindow = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status", title: "Status", windowID: 131),
            windowID: 131,
            sourcePID: 5_001
        )
        let exactWindow = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.other", title: "Other", windowID: 130),
            windowID: 130,
            sourcePID: 8_001
        )

        let refreshed = MenuBarClickTargetPolicy.refreshedTarget(
            matching: stale,
            in: [sameIdentityNewWindow, exactWindow]
        )

        XCTAssertEqual(refreshed, exactWindow)
    }

    func testClickTargetPolicyFallsBackToStableIdentityAndPIDWhenWindowIDChanges() {
        let stale = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status", title: "Status", windowID: 132),
            windowID: 132,
            sourcePID: 5_002
        )
        let wrongPID = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status", title: "Status", windowID: 133),
            windowID: 133,
            sourcePID: 9_999
        )
        let matching = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status", title: "Status", windowID: 134),
            windowID: 134,
            sourcePID: 5_002
        )

        XCTAssertEqual(
            MenuBarClickTargetPolicy.refreshedTarget(
                matching: stale,
                in: [wrongPID, matching]
            ),
            matching
        )
        XCTAssertNil(
            MenuBarClickTargetPolicy.refreshedTarget(
                matching: stale,
                in: [wrongPID]
            )
        )
    }

    func testClickTargetPolicyUsesBoundsCenterForClickPoint() {
        XCTAssertEqual(
            MenuBarClickTargetPolicy.clickPoint(
                for: CGRect(x: 10, y: 20, width: 30, height: 22)
            ),
            CGPoint(x: 25, y: 31)
        )
    }

    func testAccessibilityPressPolicyRejectsMissingCandidates() {
        XCTAssertEqual(
            MenuBarAccessibilityPressPolicy.targetCandidate(
                for: CGRect(x: 100, y: 20, width: 24, height: 22),
                candidates: []
            ),
            .noTarget
        )
    }

    func testAccessibilityPressPolicyUsesSingleCandidateWithoutFrame() {
        XCTAssertEqual(
            MenuBarAccessibilityPressPolicy.targetCandidate(
                for: CGRect(x: 100, y: 20, width: 24, height: 22),
                candidates: [
                    .init(index: 3, frame: nil),
                ]
            ),
            .useCandidate(index: 3)
        )
    }

    func testAccessibilityPressPolicyChoosesNearestCandidateWithinTolerance() {
        let itemBounds = CGRect(x: 100, y: 20, width: 24, height: 22)

        XCTAssertEqual(
            MenuBarAccessibilityPressPolicy.targetCandidate(
                for: itemBounds,
                candidates: [
                    .init(index: 0, frame: CGRect(x: 40, y: 20, width: 24, height: 22)),
                    .init(index: 1, frame: CGRect(x: 103, y: 20, width: 24, height: 22)),
                    .init(index: 2, frame: nil),
                ]
            ),
            .useCandidate(index: 1)
        )
    }

    func testAccessibilityPressPolicyRejectsMultipleCandidatesWithoutCloseFrame() {
        let itemBounds = CGRect(x: 100, y: 20, width: 24, height: 22)

        XCTAssertEqual(
            MenuBarAccessibilityPressPolicy.targetCandidate(
                for: itemBounds,
                candidates: [
                    .init(index: 0, frame: nil),
                    .init(index: 1, frame: CGRect(x: 160, y: 20, width: 24, height: 22)),
                ]
            ),
            .noTarget
        )
    }

    func testEventTimingPolicyDefaultsMoveTimeoutsByItemKind() {
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status", title: "Status"),
            windowID: 107
        )
        let bentoBox = MenuBarItem.fixture(
            tag: .controlCenter,
            windowID: 108,
            sourcePID: nil,
            ownerPID: 88
        )

        XCTAssertEqual(
            MenuBarEventTimingPolicy.defaultMoveTimeout(for: appItem),
            .milliseconds(250)
        )
        XCTAssertEqual(
            MenuBarEventTimingPolicy.defaultMoveTimeout(for: bentoBox),
            .milliseconds(300)
        )
    }

    func testEventTimingPolicyClampsAdaptiveMoveTimeouts() {
        XCTAssertEqual(
            MenuBarEventTimingPolicy.updatedMoveTimeout(
                previous: .milliseconds(250),
                measured: .milliseconds(100)
            ),
            .milliseconds(250)
        )
        XCTAssertEqual(
            MenuBarEventTimingPolicy.updatedMoveTimeout(
                previous: .milliseconds(300),
                measured: .milliseconds(500)
            ),
            .milliseconds(400)
        )
        XCTAssertEqual(
            MenuBarEventTimingPolicy.updatedMoveTimeout(
                previous: .milliseconds(500),
                measured: .milliseconds(800)
            ),
            .milliseconds(500)
        )
    }

    func testEventTimingPolicyDefaultsClickTimeoutsByAppNamespace() {
        let ordinary = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status", title: "Status"),
            windowID: 109
        )
        let knownSlow = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bitsplash.PasteNow.Helper", title: "Paste"),
            windowID: 110
        )

        XCTAssertEqual(
            MenuBarEventTimingPolicy.defaultClickTimeout(for: ordinary),
            .milliseconds(350)
        )
        XCTAssertEqual(
            MenuBarEventTimingPolicy.defaultClickTimeout(for: knownSlow),
            .milliseconds(500)
        )
    }

    func testEventTimingPolicyClampsAdaptiveClickTimeouts() {
        XCTAssertEqual(
            MenuBarEventTimingPolicy.updatedClickTimeout(
                previous: .milliseconds(200),
                measured: .milliseconds(50)
            ),
            .milliseconds(200)
        )
        XCTAssertEqual(
            MenuBarEventTimingPolicy.updatedClickTimeout(
                previous: .milliseconds(500),
                measured: .milliseconds(700)
            ),
            .milliseconds(600)
        )
        XCTAssertEqual(
            MenuBarEventTimingPolicy.updatedClickTimeout(
                previous: .milliseconds(1_000),
                measured: .milliseconds(1_400)
            ),
            .milliseconds(1_000)
        )
    }

    func testEventTimeoutCacheUsesDefaultsAndUpdatesMoveHistory() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status", title: "Status"),
            windowID: 111
        )
        var cache = MenuBarEventTimeoutCache()

        XCTAssertEqual(cache.moveTimeout(for: item), .milliseconds(250))

        cache.updateMoveTimeout(.milliseconds(500), for: item)

        XCTAssertEqual(cache.moveTimeout(for: item), .milliseconds(375))
    }

    func testEventTimeoutCacheUsesDefaultsAndUpdatesClickHistory() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status", title: "Status"),
            windowID: 112
        )
        var cache = MenuBarEventTimeoutCache()

        XCTAssertEqual(cache.clickTimeout(for: item), .milliseconds(350))

        let updated = cache.updateClickTimeout(.milliseconds(650), for: item)

        XCTAssertEqual(updated, .milliseconds(500))
        XCTAssertEqual(cache.clickTimeout(for: item), .milliseconds(500))
    }

    func testEventTimeoutCachePrunesMoveAndClickHistoryByTag() {
        let kept = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.kept", title: "Kept"),
            windowID: 113
        )
        let removed = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.removed", title: "Removed"),
            windowID: 114
        )
        var cache = MenuBarEventTimeoutCache()

        cache.updateMoveTimeout(.milliseconds(500), for: kept)
        cache.updateMoveTimeout(.milliseconds(500), for: removed)
        cache.updateClickTimeout(.milliseconds(650), for: kept)
        cache.updateClickTimeout(.milliseconds(650), for: removed)

        cache.pruneMoveTimeouts(keeping: [kept.tag])
        cache.pruneClickTimeouts(keeping: [kept.tag])

        XCTAssertEqual(cache.moveTimeout(for: kept), .milliseconds(375))
        XCTAssertEqual(cache.clickTimeout(for: kept), .milliseconds(500))
        XCTAssertEqual(cache.moveTimeout(for: removed), .milliseconds(250))
        XCTAssertEqual(cache.clickTimeout(for: removed), .milliseconds(350))
    }

    func testSyntheticEventRuntimeTracksMovePacing() {
        let now = ContinuousClock.now
        var runtime = MenuBarSyntheticEventRuntime()

        XCTAssertNil(runtime.moveOperationBuffer(now: now))
        XCTAssertFalse(runtime.lastMoveOperationOccurred(within: .seconds(1), now: now))

        runtime.recordMoveOperation(now: now.advanced(by: .milliseconds(-10)))

        XCTAssertTrue(runtime.lastMoveOperationOccurred(within: .milliseconds(20), now: now))
        XCTAssertEqual(runtime.moveOperationBuffer(now: now), .milliseconds(15))
    }

    func testSyntheticEventRuntimeOwnsCursorSuppression() {
        var runtime = MenuBarSyntheticEventRuntime()

        XCTAssertTrue(runtime.shouldManageCursor)

        runtime.beginCursorManagementSuppression()

        XCTAssertFalse(runtime.shouldManageCursor)

        runtime.endCursorManagementSuppression()

        XCTAssertTrue(runtime.shouldManageCursor)
    }

    func testSyntheticEventRuntimeUpdatesAndPrunesAdaptiveTimeouts() {
        let kept = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.kept", title: "Kept"),
            windowID: 115
        )
        let removed = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.removed", title: "Removed"),
            windowID: 116
        )
        var runtime = MenuBarSyntheticEventRuntime()

        runtime.recordMoveFinished(timeout: .milliseconds(500), for: kept)
        runtime.recordMoveFinished(timeout: .milliseconds(500), for: removed)
        runtime.recordClickSuccess(.milliseconds(650), for: kept)
        runtime.recordClickSuccess(.milliseconds(650), for: removed)

        runtime.pruneTimeouts(keeping: [kept])

        XCTAssertEqual(runtime.moveTimeout(for: kept), .milliseconds(375))
        XCTAssertEqual(runtime.clickTimeout(for: kept), .milliseconds(500))
        XCTAssertEqual(runtime.moveTimeout(for: removed), .milliseconds(250))
        XCTAssertEqual(runtime.clickTimeout(for: removed), .milliseconds(350))
    }

    func testEventOperationGateSerializesUntilRelease() async throws {
        let gate = MenuBarEventOperationGate()

        let firstPermit = try await gate.acquire(timeout: .milliseconds(20))
        XCTAssertFalse(firstPermit.recoveredFromTimeout)

        let secondAcquire = Task {
            try await gate.acquire(timeout: .milliseconds(500))
        }

        try await Task.sleep(for: .milliseconds(20))
        await gate.release()

        let secondPermit = try await secondAcquire.value
        XCTAssertFalse(secondPermit.recoveredFromTimeout)
        await gate.release()
    }

    func testEventOperationGateResetsLeakedPermitAfterAcquireTimeout() async throws {
        let gate = MenuBarEventOperationGate()

        _ = try await gate.acquire(timeout: .milliseconds(20))

        let recoveredPermit = try await gate.acquire(timeout: .milliseconds(20))
        XCTAssertTrue(recoveredPermit.recoveredFromTimeout)
        await gate.release()
    }

    func testEventOperationGateFailsWhenResetCannotAcquirePermit() async throws {
        let gate = MenuBarEventOperationGate(permits: 0)

        do {
            _ = try await gate.acquire(timeout: .milliseconds(10))
            XCTFail("Expected acquire to time out after reset")
        } catch let error as MenuBarEventOperationGate.AcquireError {
            XCTAssertEqual(error, .timedOutAfterReset)
        }
    }

    func testEventPacingPolicyComputesMoveOperationBuffer() {
        XCTAssertEqual(
            MenuBarEventPacingPolicy.moveOperationBuffer(elapsedSinceLastMove: .zero),
            .milliseconds(25)
        )
        XCTAssertEqual(
            MenuBarEventPacingPolicy.moveOperationBuffer(elapsedSinceLastMove: .milliseconds(10)),
            .milliseconds(15)
        )
        XCTAssertEqual(
            MenuBarEventPacingPolicy.moveOperationBuffer(elapsedSinceLastMove: .milliseconds(25)),
            .zero
        )
        XCTAssertEqual(
            MenuBarEventPacingPolicy.moveOperationBuffer(elapsedSinceLastMove: .milliseconds(80)),
            .zero
        )
    }

    func testEventPacingPolicyChoosesRehideSettleDelayByCaller() {
        XCTAssertEqual(
            MenuBarEventPacingPolicy.rehideSettleDelay(isCalledFromTemporarilyShow: true),
            .milliseconds(50)
        )
        XCTAssertEqual(
            MenuBarEventPacingPolicy.rehideSettleDelay(isCalledFromTemporarilyShow: false),
            .milliseconds(250)
        )
    }

    func testEventPacingPolicyPinsInteractiveDelays() {
        XCTAssertEqual(MenuBarEventPacingPolicy.inputPauseQuietWindow, .milliseconds(50))
        XCTAssertEqual(MenuBarEventPacingPolicy.moveResponsePollInterval, .milliseconds(10))
        XCTAssertEqual(MenuBarEventPacingPolicy.moveWarpSettleDelay, .milliseconds(20))
        XCTAssertEqual(MenuBarEventPacingPolicy.clickWarpSettleDelay, .milliseconds(10))
        XCTAssertEqual(MenuBarEventPacingPolicy.revealedItemFastSettleTimeout, .milliseconds(150))
        XCTAssertEqual(MenuBarEventPacingPolicy.popupCaptureDelay, .milliseconds(100))
    }

    func testTemporaryRevealPolicyCapturesReturnRouteWithFallbackNeighbor() throws {
        let leftNeighbor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.left", title: "Left"),
            windowID: 201,
            sourcePID: 2001,
            ownerPID: 2001
        )
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.item", title: "Item"),
            windowID: 202,
            sourcePID: 2002,
            ownerPID: 2002
        )
        let rightNeighbor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.right", title: "Right"),
            windowID: 203,
            sourcePID: 2003,
            ownerPID: 2003
        )

        let route = try XCTUnwrap(
            MenuBarTemporaryRevealPolicy.captureReturnInfo(
                for: item,
                in: [leftNeighbor, item, rightNeighbor]
            )
        )

        XCTAssertEqual(route.destination, .leftOfItem(rightNeighbor))
        XCTAssertEqual(
            route.fallbackNeighbor,
            MenuBarTemporaryRevealPolicy.Neighbor(tag: leftNeighbor.tag, pid: 2001)
        )
    }

    func testTemporaryRevealPolicyCapturesLeftNeighborWhenItemIsLeftmost() throws {
        let neighbor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.neighbor", title: "Neighbor"),
            windowID: 204,
            sourcePID: 2004,
            ownerPID: 2004
        )
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.item", title: "Item"),
            windowID: 205,
            sourcePID: 2005,
            ownerPID: 2005
        )

        let route = try XCTUnwrap(
            MenuBarTemporaryRevealPolicy.captureReturnInfo(for: item, in: [neighbor, item])
        )

        XCTAssertEqual(route.destination, .rightOfItem(neighbor))
        XCTAssertNil(route.fallbackNeighbor)
    }

    func testTemporaryRevealPolicyChoosesRevealAnchorByPreference() {
        let visibleControl = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 206,
            sourcePID: nil
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 207,
            sourcePID: nil
        )
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 208
        )

        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.revealAnchor(in: [appItem, visibleControl]),
            visibleControl
        )
        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.revealAnchor(in: [hiddenControl, appItem]),
            appItem
        )
        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.revealAnchor(in: [hiddenControl]),
            hiddenControl
        )
    }

    func testTemporaryRevealPolicyResolvesReturnDestinationByFreshPrimaryNeighbor() throws {
        let staleTarget = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.target", title: "Target"),
            windowID: 209,
            sourcePID: 2009,
            ownerPID: 2009
        )
        let freshTarget = MenuBarItem.fixture(
            tag: staleTarget.tag,
            windowID: 210,
            sourcePID: 2009,
            ownerPID: 2009
        )
        let route = MenuBarTemporaryRevealPolicy.ReturnRoute(
            destination: .leftOfItem(staleTarget),
            fallbackNeighbor: nil,
            originalSection: .hidden
        )

        let resolution = try XCTUnwrap(
            MenuBarTemporaryRevealPolicy.resolveReturnDestination(for: route, in: [freshTarget])
        )

        XCTAssertEqual(resolution.source, .primaryNeighbor)
        XCTAssertEqual(resolution.destination, .leftOfItem(freshTarget))
    }

    func testTemporaryRevealPolicyResolvesReturnDestinationByFallbackNeighbor() throws {
        let staleTarget = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.target", title: "Target"),
            windowID: 211,
            sourcePID: 2011,
            ownerPID: 2011
        )
        let fallback = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.fallback", title: "Fallback"),
            windowID: 212,
            sourcePID: 2012,
            ownerPID: 2012
        )
        let route = MenuBarTemporaryRevealPolicy.ReturnRoute(
            destination: .leftOfItem(staleTarget),
            fallbackNeighbor: MenuBarTemporaryRevealPolicy.Neighbor(tag: fallback.tag, pid: 2012),
            originalSection: .hidden
        )

        let resolution = try XCTUnwrap(
            MenuBarTemporaryRevealPolicy.resolveReturnDestination(for: route, in: [fallback])
        )

        XCTAssertEqual(resolution.source, .fallbackNeighbor)
        XCTAssertEqual(resolution.destination, .rightOfItem(fallback))
    }

    func testTemporaryRevealPolicyFallsBackToSectionControlWhenNeighborsDisappear() throws {
        let staleTarget = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.target", title: "Target"),
            windowID: 213,
            sourcePID: 2013,
            ownerPID: 2013
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 214,
            sourcePID: nil
        )
        let route = MenuBarTemporaryRevealPolicy.ReturnRoute(
            destination: .leftOfItem(staleTarget),
            fallbackNeighbor: nil,
            originalSection: .alwaysHidden
        )

        let resolution = try XCTUnwrap(
            MenuBarTemporaryRevealPolicy.resolveReturnDestination(for: route, in: [hiddenControl])
        )

        XCTAssertEqual(resolution.source, .sectionControl)
        XCTAssertEqual(resolution.destination, .leftOfItem(hiddenControl))
    }

    func testTemporaryRevealPolicyPreservesMetadataWhenMoveOutcomeIsUnknown() {
        let origin = CGPoint(x: 10, y: 20)

        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.metadataDecisionAfterMoveError(
                preMoveOrigin: origin,
                currentOrigin: origin
            ),
            .discardPendingRelocation
        )
        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.metadataDecisionAfterMoveError(
                preMoveOrigin: origin,
                currentOrigin: CGPoint(x: 11, y: 20)
            ),
            .preservePendingRelocation
        )
        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.metadataDecisionAfterMoveError(
                preMoveOrigin: nil,
                currentOrigin: nil
            ),
            .preservePendingRelocation
        )
    }

    func testTemporaryRevealPolicyBuildsPendingMetadataForRecovery() throws {
        let neighbor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.neighbor", title: "Neighbor"),
            windowID: 215
        )
        let metadata = MenuBarTemporaryRevealPolicy.pendingMetadata(
            originalSection: .alwaysHidden,
            returnDestination: .rightOfItem(neighbor)
        )

        let destination = try XCTUnwrap(
            PendingLedger.PendingReturnDestination(
                storageValue: metadata.returnDestinationStorageValue
            )
        )

        XCTAssertEqual(metadata.relocationValue, PendingLedger.sectionKey(for: .alwaysHidden))
        XCTAssertEqual(destination.neighborTagIdentifier, neighbor.tag.tagIdentifier)
        XCTAssertEqual(destination.position, .right)
    }

    func testTemporaryRevealPolicyMutatesPendingMetadataAfterMoveError() {
        let neighbor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.neighbor", title: "Neighbor"),
            windowID: 216
        )
        let metadata = MenuBarTemporaryRevealPolicy.pendingMetadata(
            originalSection: .hidden,
            returnDestination: .leftOfItem(neighbor)
        )
        let origin = CGPoint(x: 10, y: 20)

        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.pendingMetadataMutationAfterMoveError(
                preMoveOrigin: origin,
                currentOrigin: origin,
                metadata: metadata
            ),
            .discard
        )
        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.pendingMetadataMutationAfterMoveError(
                preMoveOrigin: origin,
                currentOrigin: CGPoint(x: 11, y: 20),
                metadata: metadata
            ),
            .preserve(metadata)
        )
        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.pendingMetadataMutationAfterMoveError(
                preMoveOrigin: nil,
                currentOrigin: nil,
                metadata: metadata
            ),
            .preserve(metadata)
        )
    }

    func testTemporaryRevealPolicySettlesAfterRepeatedNonNilBounds() {
        let bounds = CGRect(x: 100, y: 20, width: 24, height: 22)

        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.positionSettleDecision(
                previousBounds: bounds,
                currentBounds: bounds
            ),
            .settled
        )
    }

    func testTemporaryRevealPolicyKeepsWaitingForNilOrChangingBounds() {
        let previous = CGRect(x: 100, y: 20, width: 24, height: 22)
        let current = CGRect(x: 110, y: 20, width: 24, height: 22)

        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.positionSettleDecision(
                previousBounds: nil,
                currentBounds: nil
            ),
            .keepWaiting(nextPreviousBounds: nil)
        )
        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.positionSettleDecision(
                previousBounds: previous,
                currentBounds: current
            ),
            .keepWaiting(nextPreviousBounds: current)
        )
    }

    func testTemporaryRevealPolicyDetectsOriginDeparture() {
        let origin = CGPoint(x: 100, y: 20)

        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.originDepartureDecision(
                previousOrigin: origin,
                currentOrigin: nil
            ),
            .keepWaiting
        )
        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.originDepartureDecision(
                previousOrigin: origin,
                currentOrigin: origin
            ),
            .keepWaiting
        )
        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.originDepartureDecision(
                previousOrigin: origin,
                currentOrigin: CGPoint(x: 101, y: 20)
            ),
            .departed
        )
    }

    func testTemporaryRevealAdmissionBlocksOnlyStuckDifferentItems() {
        let requestedTag = MenuBarItemTag.appItem(bundleID: "com.example.requested", title: "Requested")
        let transientTag = MenuBarItemTag.appItem(bundleID: "com.example.transient", title: "Transient")
        let stuckTag = MenuBarItemTag.appItem(bundleID: "com.example.stuck", title: "Stuck")

        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.admissionAfterForcedRehide(
                outstandingContexts: [
                    .init(tag: transientTag, rehideAttempts: 0),
                    .init(tag: requestedTag, rehideAttempts: 4),
                ],
                requestedTag: requestedTag
            ),
            .proceed(removeExistingMatchingContext: true)
        )

        XCTAssertEqual(
            MenuBarTemporaryRevealPolicy.admissionAfterForcedRehide(
                outstandingContexts: [
                    .init(tag: transientTag, rehideAttempts: 0),
                    .init(tag: stuckTag, rehideAttempts: 1),
                ],
                requestedTag: requestedTag
            ),
            .block(stuckTags: [stuckTag])
        )
    }

    @MainActor
    func testTemporaryRevealExecutorMovesClicksAndSchedulesRehide() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.reveal", title: "Reveal", windowID: 701),
            windowID: 701,
            sourcePID: 7_001
        )
        let returnNeighbor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.neighbor", title: "Neighbor", windowID: 702),
            windowID: 702,
            sourcePID: 7_002
        )
        let visibleControl = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 703,
            sourcePID: nil
        )
        let harness = TemporaryRevealExecutorHarness()
        harness.observedItems = [item, returnNeighbor, visibleControl]

        let outcome = await MenuBarTemporaryRevealExecutor.execute(
            item: item,
            mouseButton: .left,
            resolvedDisplayID: 99,
            originalSection: .alwaysHidden,
            fastPath: true,
            operations: harness.operations()
        )

        XCTAssertEqual(outcome.result, .movedAndClicked)
        XCTAssertEqual(harness.appendedContexts.map(\.tag), [item.tag])
        XCTAssertEqual(harness.appendedContexts.first?.displayID, 99)
        XCTAssertEqual(harness.recordedMetadataValues.first?.relocationValue, "alwaysHidden")
        XCTAssertEqual(harness.recordedMetadataTags, [item.tag.tagIdentifier])
        XCTAssertEqual(harness.moveDestinations, [.leftOfItem(visibleControl)])
        XCTAssertEqual(harness.moveAttemptBudgets, [2])
        XCTAssertEqual(harness.clickedItems, [item])
        XCTAssertEqual(harness.clickAttemptBudgets, [1])
        XCTAssertEqual(harness.scheduleCount, 1)
        XCTAssertEqual(harness.persistCount, 1)
        XCTAssertEqual(
            harness.events,
            [
                "hasContexts", "observe-99", "recordPending", "persist",
                "begin", "origin", "move-2", "append", "cancel",
                "refresh", "ids", "electron", "click-1", "sleep",
                "window", "timer", "end",
            ]
        )
    }

    @MainActor
    func testTemporaryRevealExecutorBlocksWhenForcedRehideLeavesStuckContexts() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.requested", title: "Requested", windowID: 711),
            windowID: 711,
            sourcePID: 7_011
        )
        let stuckTag = MenuBarItemTag.appItem(
            bundleID: "com.example.stuck",
            title: "Stuck",
            windowID: 712
        )
        let harness = TemporaryRevealExecutorHarness()
        harness.hasTemporaryContexts = true
        harness.outstandingContexts = [.init(tag: stuckTag, rehideAttempts: 1)]

        let outcome = await MenuBarTemporaryRevealExecutor.execute(
            item: item,
            mouseButton: .left,
            resolvedDisplayID: 99,
            originalSection: .hidden,
            fastPath: false,
            operations: harness.operations()
        )

        XCTAssertEqual(outcome.result, .showFailed)
        XCTAssertEqual(harness.forceRehideCount, 1)
        XCTAssertEqual(harness.scheduleCount, 1)
        XCTAssertTrue(harness.recordedMetadataTags.isEmpty)
        XCTAssertTrue(harness.appendedContexts.isEmpty)
        XCTAssertEqual(
            harness.events,
            ["hasContexts", "cancel", "forceRehide", "outstanding", "timer"]
        )
    }

    @MainActor
    func testTemporaryRevealExecutorClearsPendingMetadataWhenMoveFailsWithoutMovement() async {
        struct TemporaryRevealMoveError: Error {}

        let origin = CGPoint(x: 40, y: 12)
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.fail", title: "Fail", windowID: 721),
            windowID: 721,
            sourcePID: 7_021
        )
        let returnNeighbor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.neighbor", title: "Neighbor", windowID: 722),
            windowID: 722,
            sourcePID: 7_022
        )
        let visibleControl = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 723,
            sourcePID: nil
        )
        let harness = TemporaryRevealExecutorHarness()
        harness.observedItems = [item, returnNeighbor, visibleControl]
        harness.windowOriginSequence = [origin, origin]
        harness.moveError = TemporaryRevealMoveError()

        let outcome = await MenuBarTemporaryRevealExecutor.execute(
            item: item,
            mouseButton: .left,
            resolvedDisplayID: 99,
            originalSection: .hidden,
            fastPath: false,
            operations: harness.operations()
        )

        XCTAssertEqual(outcome.result, .showFailed)
        XCTAssertEqual(harness.recordedMetadataTags, [item.tag.tagIdentifier])
        XCTAssertEqual(harness.clearedTags, [item.tag.tagIdentifier])
        XCTAssertEqual(harness.persistCount, 2)
        XCTAssertTrue(harness.appendedContexts.isEmpty)
        XCTAssertEqual(harness.scheduleCount, 0)
        XCTAssertEqual(
            harness.events,
            [
                "hasContexts", "observe-99", "recordPending", "persist",
                "begin", "origin", "move-nil", "origin", "clear",
                "persist", "end",
            ]
        )
    }

    @MainActor
    func testTemporaryRevealExecutorFallsBackToFreshClickTarget() async {
        struct TemporaryRevealClickError: Error {}

        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.click", title: "Click", windowID: 731),
            windowID: 731,
            sourcePID: 7_031
        )
        let refreshedItem = MenuBarItem.fixture(
            tag: item.tag,
            windowID: 732,
            sourcePID: 7_031
        )
        let returnNeighbor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.neighbor", title: "Neighbor", windowID: 733),
            windowID: 733,
            sourcePID: 7_033
        )
        let visibleControl = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 734,
            sourcePID: nil
        )
        let harness = TemporaryRevealExecutorHarness()
        harness.observedItems = [item, returnNeighbor, visibleControl]
        harness.refreshedTargets = [item, refreshedItem]
        harness.clickErrors = [TemporaryRevealClickError()]

        let outcome = await MenuBarTemporaryRevealExecutor.execute(
            item: item,
            mouseButton: .left,
            resolvedDisplayID: 99,
            originalSection: .hidden,
            fastPath: true,
            operations: harness.operations()
        )

        XCTAssertEqual(outcome.result, .movedAndClicked)
        XCTAssertEqual(harness.clickedItems, [item, refreshedItem])
        XCTAssertEqual(harness.clickAttemptBudgets, [1, 3])
        XCTAssertEqual(harness.scheduleCount, 1)
    }

    func testTemporaryRevealRuntimeBuildsPlannerSnapshotsFromContexts() {
        let fallback = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.fallback", title: "Fallback", windowID: 301),
            windowID: 301,
            sourcePID: 3001
        )
        let first = temporaryRevealContext(
            tag: .appItem(bundleID: "com.example.first", title: "First", windowID: 101),
            sourcePID: 1001,
            fallback: fallback,
            originalSection: .hidden
        )
        let second = temporaryRevealContext(
            tag: .appItem(bundleID: "com.example.second", title: "Second", windowID: 102),
            sourcePID: 1002,
            originalSection: .alwaysHidden
        )
        first.rehideAttempts = 2
        var runtime = MenuBarTemporaryRevealRuntime()

        runtime.append(first)
        runtime.append(second)

        XCTAssertEqual(runtime.activeTagIdentifiers, [first.tag.tagIdentifier, second.tag.tagIdentifier])
        XCTAssertEqual(
            runtime.outstandingContexts,
            [
                .init(tag: first.tag, rehideAttempts: 2),
                .init(tag: second.tag, rehideAttempts: 0),
            ]
        )
        XCTAssertEqual(
            runtime.cachePopulationContexts,
            [
                .init(
                    tag: first.tag,
                    sourcePID: 1001,
                    originalSection: .hidden,
                    destination: first.returnDestination
                ),
                .init(
                    tag: second.tag,
                    sourcePID: 1002,
                    originalSection: .alwaysHidden,
                    destination: second.returnDestination
                ),
            ]
        )
        XCTAssertEqual(
            runtime.relocationPlanningContexts,
            [
                .init(tag: first.tag, fallbackNeighbor: fallback.tag),
                .init(tag: second.tag, fallbackNeighbor: nil),
            ]
        )
    }

    func testTemporaryRevealRuntimeDrainsRestoresAndQueuesFailedContextsInRetryOrder() {
        let first = temporaryRevealContext(
            tag: .appItem(bundleID: "com.example.first", title: "First", windowID: 101)
        )
        let second = temporaryRevealContext(
            tag: .appItem(bundleID: "com.example.second", title: "Second", windowID: 102)
        )
        var runtime = MenuBarTemporaryRevealRuntime()

        runtime.append(first)
        runtime.append(second)

        XCTAssertEqual(runtime.drainContexts().map(\.tag), [first.tag, second.tag])
        XCTAssertTrue(runtime.isEmpty)

        runtime.restoreContexts([first, second])

        XCTAssertEqual(runtime.drainContexts().map(\.tag), [first.tag, second.tag])

        runtime.appendFailedContextsForRetry([first, second])

        XCTAssertEqual(runtime.contexts.map(\.tag), [second.tag, first.tag])
    }

    func testTemporaryRevealRuntimeRemovesContextsMatchingIgnoringWindowID() {
        let original = temporaryRevealContext(
            tag: .appItem(bundleID: "com.example.item", title: "Item", windowID: 101)
        )
        let relaunched = temporaryRevealContext(
            tag: .appItem(bundleID: "com.example.item", title: "Item", windowID: 202)
        )
        let other = temporaryRevealContext(
            tag: .appItem(bundleID: "com.example.other", title: "Other", windowID: 303)
        )
        var runtime = MenuBarTemporaryRevealRuntime()

        runtime.append(original)
        runtime.append(relaunched)
        runtime.append(other)

        let removed = runtime.removeContexts(
            matching: .appItem(bundleID: "com.example.item", title: "Item", windowID: 404)
        )

        XCTAssertEqual(removed.map(\.tag), [original.tag, relaunched.tag])
        XCTAssertEqual(runtime.contexts.map(\.tag), [other.tag])
    }

    func testTemporaryRevealResultNamesRemainStableForOverlayLogging() {
        XCTAssertEqual(
            String(describing: MenuBarTemporaryRevealResult.showFailed),
            "showFailed"
        )
        XCTAssertEqual(
            String(describing: MenuBarTemporaryRevealResult.movedAndClicked),
            "movedAndClicked"
        )
        XCTAssertEqual(
            String(describing: MenuBarTemporaryRevealResult.movedButClickFailed),
            "movedButClickFailed"
        )
    }

    func testTemporaryRevealRuntimeCancelsScheduledRehideTriggers() {
        var cancellableWasCancelled = false
        let timer = Timer(timeInterval: 10, repeats: false) { _ in }
        let cancellable = AnyCancellable {
            cancellableWasCancelled = true
        }
        var runtime = MenuBarTemporaryRevealRuntime()

        runtime.attachRehideTimer(timer)
        runtime.attachFrontmostApplicationCancellable(cancellable)

        XCTAssertTrue(runtime.hasScheduledRehideTrigger)

        runtime.cancelRehideTriggers()

        XCTAssertFalse(runtime.hasScheduledRehideTrigger)
        XCTAssertFalse(timer.isValid)
        XCTAssertTrue(cancellableWasCancelled)
    }

    func testTemporaryRevealRuntimeCancelAllClearsContextsAndTriggers() {
        var runtime = MenuBarTemporaryRevealRuntime()
        let timer = Timer(timeInterval: 10, repeats: false) { _ in }

        runtime.append(temporaryRevealContext())
        runtime.attachRehideTimer(timer)

        runtime.cancelAll()

        XCTAssertTrue(runtime.isEmpty)
        XCTAssertFalse(runtime.hasScheduledRehideTrigger)
        XCTAssertFalse(timer.isValid)
    }

    func testPopupVisibilityPolicyTracksDirectMenuWindowsByOnScreenState() {
        let popupLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))

        XCTAssertTrue(
            MenuBarPopupVisibilityPolicy.trackedWindowIsShowing(
                popupObservation(layer: popupLayer, isOnScreen: true)
            )
        )
        XCTAssertFalse(
            MenuBarPopupVisibilityPolicy.trackedWindowIsShowing(
                popupObservation(layer: popupLayer, isOnScreen: false)
            )
        )
    }

    func testPopupVisibilityPolicyKeepsAccessoryAndMenuSizedNonstandardWindowsShowing() {
        XCTAssertTrue(
            MenuBarPopupVisibilityPolicy.trackedWindowIsShowing(
                popupObservation(
                    layer: 0,
                    height: 20,
                    appActivationPolicy: .accessory,
                    appIsActive: false
                )
            )
        )
        XCTAssertTrue(
            MenuBarPopupVisibilityPolicy.trackedWindowIsShowing(
                popupObservation(
                    layer: 0,
                    height: 80,
                    appActivationPolicy: .regular,
                    appIsActive: false
                )
            )
        )
        XCTAssertFalse(
            MenuBarPopupVisibilityPolicy.trackedWindowIsShowing(
                popupObservation(
                    layer: 0,
                    height: 20,
                    appActivationPolicy: .regular,
                    appIsActive: false
                )
            )
        )
        XCTAssertTrue(
            MenuBarPopupVisibilityPolicy.trackedWindowIsShowing(
                popupObservation(
                    layer: 0,
                    height: 20,
                    appActivationPolicy: .regular,
                    appIsActive: true
                )
            )
        )
    }

    func testPopupVisibilityPolicyUsesGracePeriodForMissingTrackedWindow() {
        let firstShownAt = Date(timeIntervalSince1970: 100)

        XCTAssertTrue(
            MenuBarPopupVisibilityPolicy.shouldAssumeShowingDuringGrace(
                firstShownAt: firstShownAt,
                now: Date(timeIntervalSince1970: 101.9)
            )
        )
        XCTAssertFalse(
            MenuBarPopupVisibilityPolicy.shouldAssumeShowingDuringGrace(
                firstShownAt: firstShownAt,
                now: Date(timeIntervalSince1970: 102)
            )
        )
    }

    func testPopupVisibilityPolicyFindsOnlyMenuLikeFallbackWindowsForSourcePID() {
        let sourcePID: pid_t = 4321
        let popupLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        let mainMenuLayer = Int(CGWindowLevelForKey(.mainMenuWindow))

        XCTAssertFalse(
            MenuBarPopupVisibilityPolicy.appHasVisiblePopup(
                sourcePID: sourcePID,
                windows: [
                    popupObservation(ownerPID: 9999, layer: popupLayer, height: 80),
                    popupObservation(ownerPID: sourcePID, layer: statusLayer, height: 22),
                    popupObservation(ownerPID: sourcePID, layer: popupLayer, height: 80, isOnScreen: false),
                ]
            )
        )
        XCTAssertTrue(
            MenuBarPopupVisibilityPolicy.appHasVisiblePopup(
                sourcePID: sourcePID,
                windows: [
                    popupObservation(ownerPID: sourcePID, layer: mainMenuLayer, height: 80),
                ]
            )
        )
    }

    func testMenuOpenProbePolicyUsesOnlyFreshPositiveCache() {
        let now = ContinuousClock.now

        XCTAssertEqual(
            MenuBarMenuOpenProbePolicy.cachedResultDecision(
                cachedResult: true,
                cachedAt: now.advanced(by: .milliseconds(-249)),
                now: now
            ),
            .useCachedOpenMenu
        )
        XCTAssertEqual(
            MenuBarMenuOpenProbePolicy.cachedResultDecision(
                cachedResult: true,
                cachedAt: now.advanced(by: .milliseconds(-251)),
                now: now
            ),
            .probe
        )
        XCTAssertEqual(
            MenuBarMenuOpenProbePolicy.cachedResultDecision(
                cachedResult: false,
                cachedAt: now,
                now: now
            ),
            .probe
        )
    }

    func testMenuOpenProbeRuntimeCachesOnlyPositiveProbeResults() {
        let now = ContinuousClock.now
        var runtime = MenuBarMenuOpenProbeRuntime()

        XCTAssertEqual(runtime.cachedResultDecision(now: now), .probe)

        runtime.finish(result: true, now: now)

        XCTAssertEqual(
            runtime.cachedResultDecision(now: now.advanced(by: .milliseconds(249))),
            .useCachedOpenMenu
        )
        XCTAssertEqual(
            runtime.cachedResultDecision(now: now.advanced(by: .milliseconds(251))),
            .probe
        )

        runtime.finish(result: false, now: now)

        XCTAssertEqual(runtime.cachedResultDecision(now: now), .probe)
    }

    func testMenuOpenProbeRuntimeTracksAndCancelsInFlightTask() async {
        var runtime = MenuBarMenuOpenProbeRuntime()
        let task = Task<Bool, Never> {
            while !Task.isCancelled {
                await Task.yield()
            }
            return false
        }

        runtime.start(task)

        XCTAssertNotNil(runtime.currentTask)

        runtime.cancel()

        XCTAssertNil(runtime.currentTask)
        _ = await task.value
    }

    func testMenuOpenProbeRuntimeClearsTaskOnFinish() async {
        let now = ContinuousClock.now
        var runtime = MenuBarMenuOpenProbeRuntime()
        let task = Task<Bool, Never> { true }

        runtime.start(task)
        runtime.finish(result: await task.value, now: now)

        XCTAssertNil(runtime.currentTask)
        XCTAssertEqual(runtime.cachedResultDecision(now: now), .useCachedOpenMenu)
    }

    func testMenuOpenProbeExecutorBuildsItemObservation() {
        let item = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 70,
            sourcePID: 12_345,
            ownerPID: 54_321,
            isOnScreen: false
        )

        let observation = MenuBarMenuOpenProbeExecutor.itemObservation(for: item)

        XCTAssertEqual(observation.windowID, item.windowID)
        XCTAssertEqual(observation.ownerPID, item.ownerPID)
        XCTAssertEqual(observation.sourcePID, item.sourcePID)
        XCTAssertNil(observation.ownerBundleIdentifier)
        XCTAssertTrue(observation.isControlItem)
        XCTAssertFalse(observation.isOnScreen)
    }

    func testMenuOpenProbePolicyFiltersCandidateMenuWindows() {
        let controlCenterBundleID = MenuBarItemTag.Namespace.controlCenter.description

        XCTAssertEqual(
            MenuBarMenuOpenProbePolicy.candidateMenuWindows(
                from: [
                    menuOpenWindow(windowID: 1),
                    menuOpenWindow(windowID: 2, title: "Named"),
                    menuOpenWindow(windowID: 3, isMenuRelated: false),
                    menuOpenWindow(
                        windowID: 4,
                        ownerBundleIdentifier: controlCenterBundleID
                    ),
                ],
                controlCenterBundleIdentifier: controlCenterBundleID
            ),
            [menuOpenWindow(windowID: 1)]
        )
    }

    func testMenuOpenProbePolicyUsesFastPathCandidatePIDs() {
        let controlCenterBundleID = MenuBarItemTag.Namespace.controlCenter.description
        let sourceOwnedPID: pid_t = 2002
        let directlyOwnedPID: pid_t = 3003

        let evaluation = MenuBarMenuOpenProbePolicy.fastPathEvaluation(
            cachedItems: [
                menuOpenItem(
                    windowID: 10,
                    ownerPID: 9999,
                    sourcePID: sourceOwnedPID,
                    ownerBundleIdentifier: controlCenterBundleID
                ),
                menuOpenItem(
                    windowID: 11,
                    ownerPID: directlyOwnedPID,
                    sourcePID: nil,
                    ownerBundleIdentifier: "com.example.direct"
                ),
                menuOpenItem(
                    windowID: 12,
                    ownerPID: 4004,
                    sourcePID: nil,
                    ownerBundleIdentifier: controlCenterBundleID
                ),
            ],
            candidateMenuWindows: [
                menuOpenWindow(windowID: 20, ownerPID: sourceOwnedPID),
            ],
            controlCenterBundleIdentifier: controlCenterBundleID
        )

        XCTAssertEqual(evaluation.fastPathPIDs, [sourceOwnedPID, directlyOwnedPID])
        XCTAssertEqual(evaluation.openMenuOwnerPID, sourceOwnedPID)
        XCTAssertEqual(evaluation.unresolvedWindowIDs, [12])
        XCTAssertFalse(evaluation.needsPreciseFallback)
    }

    func testMenuOpenProbePolicyFallsBackForUnresolvedControlCenterItems() {
        let controlCenterBundleID = MenuBarItemTag.Namespace.controlCenter.description
        let resolvedSourcePID: pid_t = 8080
        let evaluation = MenuBarMenuOpenProbePolicy.fastPathEvaluation(
            cachedItems: [
                menuOpenItem(
                    windowID: 30,
                    ownerPID: 4004,
                    sourcePID: nil,
                    ownerBundleIdentifier: controlCenterBundleID
                ),
                menuOpenItem(
                    windowID: 31,
                    ownerPID: 4004,
                    sourcePID: nil,
                    ownerBundleIdentifier: controlCenterBundleID,
                    isControlItem: true
                ),
            ],
            candidateMenuWindows: [
                menuOpenWindow(windowID: 40, ownerPID: resolvedSourcePID),
            ],
            controlCenterBundleIdentifier: controlCenterBundleID
        )

        XCTAssertNil(evaluation.openMenuOwnerPID)
        XCTAssertTrue(evaluation.needsPreciseFallback)
        XCTAssertEqual(evaluation.unresolvedWindowIDs, [30])
        XCTAssertEqual(
            MenuBarMenuOpenProbePolicy.preciseFallbackOpenMenuOwnerPID(
                candidateMenuWindows: evaluation.candidateMenuWindows,
                fastPathPIDs: evaluation.fastPathPIDs,
                resolvedPIDs: [resolvedSourcePID]
            ),
            resolvedSourcePID
        )
    }

    func testTemporaryRehidePolicyStartDecisionHonorsForceAndDeferrals() {
        XCTAssertEqual(
            MenuBarTemporaryRehidePolicy.startDecision(
                force: true,
                interfaceIsShowing: true,
                userInputPaused: false
            ),
            .proceed
        )
        XCTAssertEqual(
            MenuBarTemporaryRehidePolicy.startDecision(
                force: false,
                interfaceIsShowing: true,
                userInputPaused: true
            ),
            .reschedule(reason: .interfaceShowing, after: 3)
        )
        XCTAssertEqual(
            MenuBarTemporaryRehidePolicy.startDecision(
                force: false,
                interfaceIsShowing: false,
                userInputPaused: false
            ),
            .reschedule(reason: .recentUserInput, after: 1)
        )
        XCTAssertEqual(
            MenuBarTemporaryRehidePolicy.startDecision(
                force: false,
                interfaceIsShowing: false,
                userInputPaused: true
            ),
            .proceed
        )
    }

    func testTemporaryRehidePolicyRetryDelaysRespectForce() {
        XCTAssertEqual(
            MenuBarTemporaryRehidePolicy.observationMissRetryDelay(force: false),
            3
        )
        XCTAssertNil(MenuBarTemporaryRehidePolicy.observationMissRetryDelay(force: true))
        XCTAssertEqual(
            MenuBarTemporaryRehidePolicy.failedContextsRetryDelay(force: false),
            3
        )
        XCTAssertNil(MenuBarTemporaryRehidePolicy.failedContextsRetryDelay(force: true))
    }

    func testTemporaryRehidePolicyMapsMissingItemAttemptsToRecoveryActions() {
        XCTAssertEqual(
            MenuBarTemporaryRehidePolicy.missingItemAction(afterNotFoundAttempts: 1),
            .keepInMemory
        )
        XCTAssertEqual(
            MenuBarTemporaryRehidePolicy.missingItemAction(afterNotFoundAttempts: 9),
            .keepInMemory
        )
        XCTAssertEqual(
            MenuBarTemporaryRehidePolicy.missingItemAction(afterNotFoundAttempts: 10),
            .giveUpToPendingRelocation
        )
    }

    func testTemporaryRehidePolicyMapsMoveFailureAttemptsToRecoveryActions() {
        XCTAssertEqual(
            MenuBarTemporaryRehidePolicy.moveFailureAction(
                afterRehideAttempts: 1,
                windowID: 12345,
                originalSection: .hidden
            ),
            .retryImmediately
        )
        XCTAssertEqual(
            MenuBarTemporaryRehidePolicy.moveFailureAction(
                afterRehideAttempts: 3,
                windowID: 12345,
                originalSection: .hidden
            ),
            .retryLater
        )
        XCTAssertEqual(
            MenuBarTemporaryRehidePolicy.moveFailureAction(
                afterRehideAttempts: 9,
                windowID: 12345,
                originalSection: .alwaysHidden
            ),
            .waitForRelaunch(pendingRelocationValue: "waitForRelaunch:12345:alwaysHidden")
        )
    }

    @MainActor
    func testTemporaryRehideExecutorMovesContextsAndClearsPendingRelocation() async {
        let tag = MenuBarItemTag.appItem(
            bundleID: "com.example.rehide",
            title: "Rehide",
            windowID: 501
        )
        let item = MenuBarItem.fixture(tag: tag, windowID: 501, sourcePID: 2_001)
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor", windowID: 502),
            windowID: 502,
            sourcePID: 2_002
        )
        let context = temporaryRevealContext(
            tag: tag,
            sourcePID: 2_001,
            displayID: 77,
            target: anchor
        )
        var contexts = [context]
        var clearedTags = [String]()
        var events = [String]()
        var movedItems = [(MenuBarItem, MenuBarMoveDestination, CGDirectDisplayID)]()

        let outcome = await MenuBarTemporaryRehideExecutor.execute(
            force: false,
            isCalledFromTemporarilyShow: false,
            interfaceIsShowing: false,
            userInputPaused: true,
            operations: MenuBarTemporaryRehideExecutor.Operations(
                drainContexts: {
                    events.append("drain")
                    let drained = contexts
                    contexts.removeAll()
                    return drained
                },
                restoreContexts: { restoredContexts in
                    events.append("restore")
                    contexts.append(contentsOf: restoredContexts)
                },
                observeItems: {
                    events.append("observe")
                    return [item, anchor]
                },
                resolveReturnDestination: { _, _ in
                    .leftOfItem(anchor)
                },
                moveItem: { item, destination, displayID in
                    events.append("move")
                    movedItems.append((item, destination, displayID))
                },
                clearPendingRelocation: { tagIdentifier in
                    events.append("clear")
                    clearedTags.append(tagIdentifier)
                },
                markWaitForRelaunch: { _, _ in
                    XCTFail("Successful rehide should not mark wait-for-relaunch")
                },
                persistPendingRelocations: {
                    events.append("persist")
                },
                appendFailedContextsForRetry: { _ in
                    XCTFail("Successful rehide should not queue failed contexts")
                },
                scheduleRehideTimer: { _ in
                    XCTFail("Successful rehide should not schedule a retry")
                },
                beginInputSession: {
                    events.append("begin")
                },
                endInputSession: {
                    events.append("end")
                },
                hideCursor: {
                    events.append("hide")
                },
                showCursor: {
                    events.append("show")
                },
                sleepBeforeRehide: { _ in
                    events.append("sleep")
                }
            ),
            diagnostics: MenuBarTemporaryRehideExecutor.Diagnostics(
                recordRehideStart: {
                    events.append("rehide")
                },
                recordAllSucceeded: {
                    events.append("success")
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarTemporaryRehideExecutor.Outcome(
                movedCount: 1,
                failedContextCount: 0,
                handedOffCount: 0,
                stopReason: .completed
            )
        )
        XCTAssertEqual(contexts.map(\.tag), [])
        XCTAssertEqual(clearedTags, [tag.tagIdentifier])
        XCTAssertEqual(movedItems.first?.0, item)
        XCTAssertEqual(movedItems.first?.1, .leftOfItem(anchor))
        XCTAssertEqual(movedItems.first?.2, 77)
        XCTAssertEqual(
            events,
            ["drain", "observe", "begin", "sleep", "rehide", "hide", "move", "clear", "persist", "success", "show", "end"]
        )
    }

    @MainActor
    func testTemporaryRehideExecutorDefersBeforeDrainingWhenInterfaceIsShowing() async {
        var drained = false
        var scheduledDelays = [TimeInterval]()
        var deferrals = [MenuBarTemporaryRehidePolicy.StartDeferralReason]()

        let outcome = await MenuBarTemporaryRehideExecutor.execute(
            force: false,
            isCalledFromTemporarilyShow: false,
            interfaceIsShowing: true,
            userInputPaused: true,
            operations: MenuBarTemporaryRehideExecutor.Operations(
                drainContexts: {
                    drained = true
                    return []
                },
                restoreContexts: { _ in
                    XCTFail("Deferred rehide should not restore contexts")
                },
                observeItems: {
                    XCTFail("Deferred rehide should not observe items")
                    return []
                },
                resolveReturnDestination: { _, _ in
                    XCTFail("Deferred rehide should not resolve destinations")
                    return nil
                },
                moveItem: { _, _, _ in
                    XCTFail("Deferred rehide should not move items")
                },
                clearPendingRelocation: { _ in
                    XCTFail("Deferred rehide should not clear pending relocation")
                },
                markWaitForRelaunch: { _, _ in
                    XCTFail("Deferred rehide should not mark wait-for-relaunch")
                },
                persistPendingRelocations: {
                    XCTFail("Deferred rehide should not persist")
                },
                appendFailedContextsForRetry: { _ in
                    XCTFail("Deferred rehide should not queue failed contexts")
                },
                scheduleRehideTimer: { delay in
                    scheduledDelays.append(delay)
                },
                beginInputSession: {
                    XCTFail("Deferred rehide should not begin an input session")
                },
                endInputSession: {
                    XCTFail("Deferred rehide should not end an input session")
                },
                hideCursor: {
                    XCTFail("Deferred rehide should not hide the cursor")
                },
                showCursor: {
                    XCTFail("Deferred rehide should not show the cursor")
                },
                sleepBeforeRehide: { _ in
                    XCTFail("Deferred rehide should not sleep")
                }
            ),
            diagnostics: MenuBarTemporaryRehideExecutor.Diagnostics(
                recordDeferral: { reason in
                    deferrals.append(reason)
                }
            )
        )

        XCTAssertFalse(drained)
        XCTAssertEqual(scheduledDelays, [3])
        XCTAssertEqual(deferrals, [.interfaceShowing])
        XCTAssertEqual(
            outcome,
            MenuBarTemporaryRehideExecutor.Outcome(
                movedCount: 0,
                failedContextCount: 0,
                handedOffCount: 0,
                stopReason: .deferred
            )
        )
    }

    @MainActor
    func testTemporaryRehideExecutorRestoresContextsWhenObservationIsUnavailable() async {
        let context = temporaryRevealContext()
        var contexts = [context]
        var scheduledDelays = [TimeInterval]()
        var restoredTags = [MenuBarItemTag]()

        let outcome = await MenuBarTemporaryRehideExecutor.execute(
            force: false,
            isCalledFromTemporarilyShow: false,
            interfaceIsShowing: false,
            userInputPaused: true,
            operations: MenuBarTemporaryRehideExecutor.Operations(
                drainContexts: {
                    let drained = contexts
                    contexts.removeAll()
                    return drained
                },
                restoreContexts: { restoredContexts in
                    restoredTags = restoredContexts.map(\.tag)
                    contexts.append(contentsOf: restoredContexts)
                },
                observeItems: {
                    nil
                },
                resolveReturnDestination: { _, _ in
                    XCTFail("Unavailable observation should not resolve destinations")
                    return nil
                },
                moveItem: { _, _, _ in
                    XCTFail("Unavailable observation should not move items")
                },
                clearPendingRelocation: { _ in
                    XCTFail("Unavailable observation should not clear pending relocation")
                },
                markWaitForRelaunch: { _, _ in
                    XCTFail("Unavailable observation should not mark wait-for-relaunch")
                },
                persistPendingRelocations: {
                    XCTFail("Unavailable observation should not persist")
                },
                appendFailedContextsForRetry: { _ in
                    XCTFail("Unavailable observation should not queue failed contexts")
                },
                scheduleRehideTimer: { delay in
                    scheduledDelays.append(delay)
                },
                beginInputSession: {
                    XCTFail("Unavailable observation should not begin an input session")
                },
                endInputSession: {
                    XCTFail("Unavailable observation should not end an input session")
                },
                hideCursor: {
                    XCTFail("Unavailable observation should not hide the cursor")
                },
                showCursor: {
                    XCTFail("Unavailable observation should not show the cursor")
                },
                sleepBeforeRehide: { _ in
                    XCTFail("Unavailable observation should not sleep")
                }
            )
        )

        XCTAssertEqual(contexts.map(\.tag), [context.tag])
        XCTAssertEqual(restoredTags, [context.tag])
        XCTAssertEqual(scheduledDelays, [3])
        XCTAssertEqual(
            outcome,
            MenuBarTemporaryRehideExecutor.Outcome(
                movedCount: 0,
                failedContextCount: 1,
                handedOffCount: 0,
                stopReason: .observationUnavailable
            )
        )
    }

    @MainActor
    func testTemporaryRehideExecutorQueuesMissingItemsForRetry() async {
        let context = temporaryRevealContext()
        var contexts = [context]
        var failedTags = [MenuBarItemTag]()
        var scheduledDelays = [TimeInterval]()
        var persistCount = 0

        let outcome = await MenuBarTemporaryRehideExecutor.execute(
            force: false,
            isCalledFromTemporarilyShow: false,
            interfaceIsShowing: false,
            userInputPaused: true,
            operations: MenuBarTemporaryRehideExecutor.Operations(
                drainContexts: {
                    let drained = contexts
                    contexts.removeAll()
                    return drained
                },
                restoreContexts: { _ in
                    XCTFail("Observed rehide should not restore drained contexts")
                },
                observeItems: {
                    []
                },
                resolveReturnDestination: { _, _ in
                    XCTFail("Missing item should not resolve destinations")
                    return nil
                },
                moveItem: { _, _, _ in
                    XCTFail("Missing item should not move")
                },
                clearPendingRelocation: { _ in
                    XCTFail("Missing item should not clear pending relocation")
                },
                markWaitForRelaunch: { _, _ in
                    XCTFail("Missing item should not mark wait-for-relaunch")
                },
                persistPendingRelocations: {
                    persistCount += 1
                },
                appendFailedContextsForRetry: { failedContexts in
                    failedTags = failedContexts.map(\.tag)
                },
                scheduleRehideTimer: { delay in
                    scheduledDelays.append(delay)
                },
                beginInputSession: {},
                endInputSession: {},
                hideCursor: {},
                showCursor: {},
                sleepBeforeRehide: { _ in }
            )
        )

        XCTAssertEqual(context.notFoundAttempts, 1)
        XCTAssertEqual(failedTags, [context.tag])
        XCTAssertEqual(scheduledDelays, [3])
        XCTAssertEqual(persistCount, 1)
        XCTAssertEqual(
            outcome,
            MenuBarTemporaryRehideExecutor.Outcome(
                movedCount: 0,
                failedContextCount: 1,
                handedOffCount: 0,
                stopReason: .retryQueued
            )
        )
    }

    @MainActor
    func testTemporaryRehideExecutorMarksWaitForRelaunchAfterRepeatedMoveFailures() async {
        struct TemporaryRehideTestError: Error {}

        let tag = MenuBarItemTag.appItem(
            bundleID: "com.example.stuck",
            title: "Stuck",
            windowID: 601
        )
        let item = MenuBarItem.fixture(tag: tag, windowID: 601, sourcePID: 6_001)
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor", windowID: 602),
            windowID: 602,
            sourcePID: 6_002
        )
        let context = temporaryRevealContext(
            tag: tag,
            sourcePID: 6_001,
            target: anchor,
            originalSection: .alwaysHidden
        )
        context.rehideAttempts = 8
        var contexts = [context]
        var markedValue: String?
        var markedTagIdentifier: String?
        var persistCount = 0

        let outcome = await MenuBarTemporaryRehideExecutor.execute(
            force: false,
            isCalledFromTemporarilyShow: false,
            interfaceIsShowing: false,
            userInputPaused: true,
            operations: MenuBarTemporaryRehideExecutor.Operations(
                drainContexts: {
                    let drained = contexts
                    contexts.removeAll()
                    return drained
                },
                restoreContexts: { _ in
                    XCTFail("Observed rehide should not restore drained contexts")
                },
                observeItems: {
                    [item, anchor]
                },
                resolveReturnDestination: { _, _ in
                    .leftOfItem(anchor)
                },
                moveItem: { _, _, _ in
                    throw TemporaryRehideTestError()
                },
                clearPendingRelocation: { _ in
                    XCTFail("Failed rehide should not clear pending relocation")
                },
                markWaitForRelaunch: { pendingRelocationValue, tagIdentifier in
                    markedValue = pendingRelocationValue
                    markedTagIdentifier = tagIdentifier
                },
                persistPendingRelocations: {
                    persistCount += 1
                },
                appendFailedContextsForRetry: { _ in
                    XCTFail("Wait-for-relaunch handoff should not queue failed contexts")
                },
                scheduleRehideTimer: { _ in
                    XCTFail("Wait-for-relaunch handoff should not schedule a retry")
                },
                beginInputSession: {},
                endInputSession: {},
                hideCursor: {},
                showCursor: {},
                sleepBeforeRehide: { _ in }
            )
        )

        XCTAssertEqual(context.rehideAttempts, 9)
        XCTAssertEqual(markedValue, "waitForRelaunch:601:alwaysHidden")
        XCTAssertEqual(markedTagIdentifier, tag.tagIdentifier)
        XCTAssertEqual(persistCount, 2)
        XCTAssertEqual(
            outcome,
            MenuBarTemporaryRehideExecutor.Outcome(
                movedCount: 0,
                failedContextCount: 0,
                handedOffCount: 1,
                stopReason: .completed
            )
        )
    }

    @MainActor
    func testPendingRelocationExecutorMovesAndClearsSectionEntry() async {
        let hiddenBounds = CGRect(x: 400, y: 0, width: 10, height: 22)
        let controlItems = MenuBarControlItems.fixture(hiddenAt: hiddenBounds)
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.pending", title: "Pending", windowID: 801),
            windowID: 801,
            bounds: CGRect(x: 500, y: 0, width: 24, height: 22)
        )
        let tagIdentifier = item.tag.tagIdentifier
        var entries = [
            tagIdentifier: PendingLedger.PendingEntry(
                tagIdentifier: tagIdentifier,
                kind: .section(.hidden)
            ),
        ]
        var clearedTags = [String]()
        var persistCount = 0
        var moved = [(MenuBarItem, MenuBarMoveDestination)]()

        let outcome = await MenuBarPendingRelocationExecutor.execute(
            tagIdentifiers: [tagIdentifier],
            items: [item, controlItems.hidden],
            controlItems: controlItems,
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [item.windowID: item.bounds],
            planningInput: emptyPendingRelocationPlanningInput(),
            operations: MenuBarPendingRelocationExecutor.Operations(
                pendingEntry: { entries[$0] },
                clearEntry: { tagIdentifier in
                    clearedTags.append(tagIdentifier)
                    entries.removeValue(forKey: tagIdentifier)
                },
                promoteWaitForRelaunch: { _, _ in
                    XCTFail("Section entry should not promote wait-for-relaunch")
                },
                persistPendingRelocations: {
                    persistCount += 1
                },
                moveItem: { item, destination in
                    moved.append((item, destination))
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarPendingRelocationExecutor.Outcome(
                didRelocate: true,
                movedCount: 1,
                clearedCount: 1,
                promotedCount: 0,
                failedMoveCount: 0
            )
        )
        XCTAssertEqual(clearedTags, [tagIdentifier])
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(moved.first?.0, item)
        XCTAssertEqual(moved.first?.1, .leftOfItem(controlItems.hidden))
        XCTAssertEqual(persistCount, 1)
    }

    @MainActor
    func testPendingRelocationExecutorPromotesWaitForRelaunchThenMoves() async {
        let hiddenBounds = CGRect(x: 400, y: 0, width: 10, height: 22)
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: hiddenBounds,
            alwaysHiddenAt: CGRect(x: 100, y: 0, width: 10, height: 22)
        )
        guard let alwaysHidden = controlItems.alwaysHidden else {
            XCTFail("Expected always-hidden control item")
            return
        }
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.promote", title: "Promote", windowID: 811),
            windowID: 811,
            bounds: CGRect(x: 500, y: 0, width: 24, height: 22)
        )
        let tagIdentifier = item.tag.tagIdentifier
        var entries = [
            tagIdentifier: PendingLedger.PendingEntry(
                tagIdentifier: tagIdentifier,
                kind: .waitForRelaunch(windowID: 700, section: .alwaysHidden)
            ),
        ]
        var promotedSections = [MenuBarSection.Name]()
        var clearedTags = [String]()
        var persistCount = 0
        var movedDestinations = [MenuBarMoveDestination]()

        let outcome = await MenuBarPendingRelocationExecutor.execute(
            tagIdentifiers: [tagIdentifier],
            items: [item, controlItems.hidden, alwaysHidden],
            controlItems: controlItems,
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [item.windowID: item.bounds],
            planningInput: emptyPendingRelocationPlanningInput(),
            operations: MenuBarPendingRelocationExecutor.Operations(
                pendingEntry: { entries[$0] },
                clearEntry: { tagIdentifier in
                    clearedTags.append(tagIdentifier)
                    entries.removeValue(forKey: tagIdentifier)
                },
                promoteWaitForRelaunch: { tagIdentifier, promotedSection in
                    promotedSections.append(promotedSection)
                    entries[tagIdentifier] = PendingLedger.PendingEntry(
                        tagIdentifier: tagIdentifier,
                        kind: .section(promotedSection)
                    )
                },
                persistPendingRelocations: {
                    persistCount += 1
                },
                moveItem: { _, destination in
                    movedDestinations.append(destination)
                }
            )
        )

        XCTAssertEqual(outcome.didRelocate, true)
        XCTAssertEqual(outcome.movedCount, 1)
        XCTAssertEqual(outcome.clearedCount, 1)
        XCTAssertEqual(outcome.promotedCount, 1)
        XCTAssertEqual(promotedSections, [.alwaysHidden])
        XCTAssertEqual(clearedTags, [tagIdentifier])
        XCTAssertEqual(movedDestinations.first, .leftOfItem(alwaysHidden))
        XCTAssertEqual(persistCount, 2)
    }

    @MainActor
    func testPendingRelocationExecutorClearsMalformedEntries() async {
        var clearedTags = [String]()
        var persistCount = 0

        let outcome = await MenuBarPendingRelocationExecutor.execute(
            tagIdentifiers: ["malformed"],
            items: [],
            controlItems: MenuBarControlItems.fixture(
                hiddenAt: CGRect(x: 400, y: 0, width: 10, height: 22)
            ),
            hiddenBounds: CGRect(x: 400, y: 0, width: 10, height: 22),
            boundsForWindowID: [:],
            planningInput: emptyPendingRelocationPlanningInput(),
            operations: MenuBarPendingRelocationExecutor.Operations(
                pendingEntry: { _ in nil },
                clearEntry: { tagIdentifier in
                    clearedTags.append(tagIdentifier)
                },
                promoteWaitForRelaunch: { _, _ in
                    XCTFail("Malformed entries should not promote")
                },
                persistPendingRelocations: {
                    persistCount += 1
                },
                moveItem: { _, _ in
                    XCTFail("Malformed entries should not move")
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarPendingRelocationExecutor.Outcome(
                didRelocate: false,
                movedCount: 0,
                clearedCount: 1,
                promotedCount: 0,
                failedMoveCount: 0
            )
        )
        XCTAssertEqual(clearedTags, ["malformed"])
        XCTAssertEqual(persistCount, 1)
    }

    @MainActor
    func testPendingRelocationExecutorKeepsEntryWhenMoveFails() async {
        struct PendingRelocationMoveError: Error {}

        let hiddenBounds = CGRect(x: 400, y: 0, width: 10, height: 22)
        let controlItems = MenuBarControlItems.fixture(hiddenAt: hiddenBounds)
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.failed", title: "Failed", windowID: 821),
            windowID: 821,
            bounds: CGRect(x: 500, y: 0, width: 24, height: 22)
        )
        let tagIdentifier = item.tag.tagIdentifier
        var persistCount = 0
        var clearedTags = [String]()

        let outcome = await MenuBarPendingRelocationExecutor.execute(
            tagIdentifiers: [tagIdentifier],
            items: [item, controlItems.hidden],
            controlItems: controlItems,
            hiddenBounds: hiddenBounds,
            boundsForWindowID: [item.windowID: item.bounds],
            planningInput: emptyPendingRelocationPlanningInput(),
            operations: MenuBarPendingRelocationExecutor.Operations(
                pendingEntry: { _ in
                    PendingLedger.PendingEntry(
                        tagIdentifier: tagIdentifier,
                        kind: .section(.hidden)
                    )
                },
                clearEntry: { tagIdentifier in
                    clearedTags.append(tagIdentifier)
                },
                promoteWaitForRelaunch: { _, _ in
                    XCTFail("Section entry should not promote")
                },
                persistPendingRelocations: {
                    persistCount += 1
                },
                moveItem: { _, _ in
                    throw PendingRelocationMoveError()
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarPendingRelocationExecutor.Outcome(
                didRelocate: false,
                movedCount: 0,
                clearedCount: 0,
                promotedCount: 0,
                failedMoveCount: 1
            )
        )
        XCTAssertTrue(clearedTags.isEmpty)
        XCTAssertEqual(persistCount, 1)
    }

    func testMoveRecoveryPolicyOnlyRestoresBlockedAlwaysHiddenMoves() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 104,
            sourcePID: 1234
        )
        let alwaysHiddenControl = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 105,
            sourcePID: nil
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 106,
            sourcePID: nil
        )
        let alwaysHiddenCommand = MenuBarMoveCommand(
            item: item,
            destination: .leftOfItem(alwaysHiddenControl),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 8
        )
        let hiddenCommand = MenuBarMoveCommand(
            item: item,
            destination: .leftOfItem(hiddenControl),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 8
        )

        XCTAssertEqual(
            MenuBarMoveRecoveryPolicy.decision(
                after: alwaysHiddenCommand,
                itemIsBlocked: true
            ),
            .restoreToVisible
        )
        XCTAssertEqual(
            MenuBarMoveRecoveryPolicy.decision(
                after: alwaysHiddenCommand,
                itemIsBlocked: false
            ),
            .none
        )
        XCTAssertEqual(
            MenuBarMoveRecoveryPolicy.decision(
                after: hiddenCommand,
                itemIsBlocked: true
            ),
            .none
        )
        XCTAssertEqual(
            MenuBarMoveRecoveryPolicy.visibleRecoveryDestination(
                hiddenControlItem: hiddenControl
            ),
            .rightOfItem(hiddenControl)
        )
    }

    @MainActor
    func testBlockedMoveRecoveryExecutorRestoresBlockedAlwaysHiddenMove() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.blocked-move", title: "BlockedMove"),
            windowID: 1_400
        )
        let alwaysHiddenControl = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 1_401,
            sourcePID: nil
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_402,
            sourcePID: nil
        )
        let command = MenuBarMoveCommand(
            item: item,
            destination: .leftOfItem(alwaysHiddenControl),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 8
        )
        let displayID: CGDirectDisplayID = 42
        var events = [String]()
        var observedCount = 0
        var moved = [(MenuBarItem, MenuBarMoveDestination, CGDirectDisplayID)]()

        let outcome = await MenuBarBlockedMoveRecoveryExecutor.execute(
            command: command,
            displayID: displayID,
            itemIsBlocked: { true },
            controlItemWindowIDs: MenuBarControlItemWindowIDs(hidden: hiddenControl.windowID),
            observeItems: {
                observedCount += 1
                return [item, alwaysHiddenControl, hiddenControl]
            },
            moveItem: { item, destination, displayID in
                moved.append((item, destination, displayID))
            },
            recordRecoveryStart: { _ in
                events.append("start")
            },
            recordRecoverySuccess: { _ in
                events.append("success")
            },
            recordRecoveryFailure: { item, error in
                XCTFail("Unexpected move recovery failure for \(item.uniqueIdentifier): \(error)")
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarBlockedMoveRecoveryExecutor.Outcome(
                attemptedRecovery: true,
                recovered: true,
                stopReason: .completed
            )
        )
        XCTAssertEqual(events, ["start", "success"])
        XCTAssertEqual(observedCount, 1)
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(moved.first?.0, item)
        guard case let .rightOfItem(anchor)? = moved.first?.1 else {
            XCTFail("Expected recovery to move to the visible side of the hidden control")
            return
        }
        XCTAssertEqual(anchor.uniqueIdentifier, hiddenControl.uniqueIdentifier)
        XCTAssertEqual(moved.first?.2, displayID)
    }

    @MainActor
    func testBlockedMoveRecoveryExecutorSkipsWhenRecoveryIsNotNeeded() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.not-blocked", title: "NotBlocked"),
            windowID: 1_410
        )
        let alwaysHiddenControl = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 1_411,
            sourcePID: nil
        )
        let command = MenuBarMoveCommand(
            item: item,
            destination: .leftOfItem(alwaysHiddenControl),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 8
        )
        var observedCount = 0
        var movedCount = 0
        var started = false

        let outcome = await MenuBarBlockedMoveRecoveryExecutor.execute(
            command: command,
            displayID: 42,
            itemIsBlocked: { false },
            controlItemWindowIDs: .unresolved,
            observeItems: {
                observedCount += 1
                return []
            },
            moveItem: { _, _, _ in
                movedCount += 1
            },
            recordRecoveryStart: { _ in
                started = true
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarBlockedMoveRecoveryExecutor.Outcome(
                attemptedRecovery: false,
                recovered: false,
                stopReason: .notNeeded
            )
        )
        XCTAssertFalse(started)
        XCTAssertEqual(observedCount, 0)
        XCTAssertEqual(movedCount, 0)
    }

    @MainActor
    func testBlockedMoveRecoveryExecutorStopsWhenHiddenControlWindowIsMissing() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.no-hidden-window", title: "NoHiddenWindow"),
            windowID: 1_420
        )
        let alwaysHiddenControl = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 1_421,
            sourcePID: nil
        )
        let command = MenuBarMoveCommand(
            item: item,
            destination: .leftOfItem(alwaysHiddenControl),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 8
        )
        var missingItems = [String]()
        var observedCount = 0
        var movedCount = 0

        let outcome = await MenuBarBlockedMoveRecoveryExecutor.execute(
            command: command,
            displayID: 42,
            itemIsBlocked: { true },
            controlItemWindowIDs: .unresolved,
            observeItems: {
                observedCount += 1
                return []
            },
            moveItem: { _, _, _ in
                movedCount += 1
            },
            recordMissingHiddenControlWindow: { item in
                missingItems.append(item.uniqueIdentifier)
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarBlockedMoveRecoveryExecutor.Outcome(
                attemptedRecovery: true,
                recovered: false,
                stopReason: .missingHiddenControlWindow
            )
        )
        XCTAssertEqual(missingItems, [item.uniqueIdentifier])
        XCTAssertEqual(observedCount, 0)
        XCTAssertEqual(movedCount, 0)
    }

    @MainActor
    func testBlockedMoveRecoveryExecutorReportsMoveFailure() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.recovery-failure", title: "RecoveryFailure"),
            windowID: 1_430
        )
        let alwaysHiddenControl = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 1_431,
            sourcePID: nil
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_432,
            sourcePID: nil
        )
        let command = MenuBarMoveCommand(
            item: item,
            destination: .leftOfItem(alwaysHiddenControl),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 8
        )
        var failedItems = [String]()

        let outcome = await MenuBarBlockedMoveRecoveryExecutor.execute(
            command: command,
            displayID: 42,
            itemIsBlocked: { true },
            controlItemWindowIDs: MenuBarControlItemWindowIDs(hidden: hiddenControl.windowID),
            observeItems: {
                [item, alwaysHiddenControl, hiddenControl]
            },
            moveItem: { _, _, _ in
                throw MenuBarEventError.cannotComplete
            },
            recordRecoverySuccess: { item in
                XCTFail("Unexpected move recovery success for \(item.uniqueIdentifier)")
            },
            recordRecoveryFailure: { item, _ in
                failedItems.append(item.uniqueIdentifier)
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarBlockedMoveRecoveryExecutor.Outcome(
                attemptedRecovery: true,
                recovered: false,
                stopReason: .moveFailed
            )
        )
        XCTAssertEqual(failedItems, [item.uniqueIdentifier])
    }

    func testSavedLayoutTriggerAppliesOnSectionDivergence() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 110,
            bounds: CGRect(x: 700, y: 0, width: 24, height: 22),
            sourcePID: 1234
        )
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 600, y: 0, width: 32, height: 22)
        )

        let decision = MenuBarSavedLayoutTrigger.evaluate(
            savedSectionOrder: ["hidden": [item.uniqueIdentifier]],
            items: [item],
            controlItems: controlItems,
            previousWindowIDs: [],
            previousDisplayID: 1,
            currentDisplayID: 1,
            relocationSuppressed: false,
            moveCooldownActive: false
        )

        XCTAssertEqual(decision, .apply(.layoutDivergence))
    }

    func testSavedLayoutTriggerSkipsPureDisplaySwitchChurn() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 210,
            bounds: CGRect(x: 700, y: 0, width: 24, height: 22),
            sourcePID: 1234
        )
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 600, y: 0, width: 32, height: 22)
        )

        let decision = MenuBarSavedLayoutTrigger.evaluate(
            savedSectionOrder: ["visible": [item.uniqueIdentifier]],
            items: [item],
            controlItems: controlItems,
            previousWindowIDs: [100, 101],
            previousDisplayID: 1,
            currentDisplayID: 2,
            relocationSuppressed: false,
            moveCooldownActive: false
        )

        XCTAssertEqual(decision, .skip(.noDetectedChange))
    }

    func testSavedLayoutTriggerMatchesIndexedSavedIdentifierByBaseIdentity() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 111,
            bounds: CGRect(x: 700, y: 0, width: 24, height: 22),
            sourcePID: 1234
        )
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 600, y: 0, width: 32, height: 22)
        )

        let decision = MenuBarSavedLayoutTrigger.evaluate(
            savedSectionOrder: ["visible": ["com.example.clock:Clock:1"]],
            items: [item],
            controlItems: controlItems,
            previousWindowIDs: [111, 112],
            previousDisplayID: 1,
            currentDisplayID: 1,
            relocationSuppressed: false,
            moveCooldownActive: false
        )

        XCTAssertEqual(decision, .apply(.windowIDChange))
    }

    func testSavedLayoutTriggerSkipsWhenNoSavedItemsArePresent() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 112,
            bounds: CGRect(x: 700, y: 0, width: 24, height: 22),
            sourcePID: 1234
        )
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 600, y: 0, width: 32, height: 22)
        )

        let decision = MenuBarSavedLayoutTrigger.evaluate(
            savedSectionOrder: ["visible": ["com.example.mail:Mail"]],
            items: [item],
            controlItems: controlItems,
            previousWindowIDs: [112, 113],
            previousDisplayID: 1,
            currentDisplayID: 1,
            relocationSuppressed: false,
            moveCooldownActive: false
        )

        XCTAssertEqual(decision, .skip(.noSavedItemsPresent))
    }

    func testSavedLayoutItemPolicyIncludesOnlyUserMovableLayoutItems() {
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.layout", title: "Layout Item"),
            windowID: 1_230
        )
        let visibleControl = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 1_231,
            sourcePID: nil
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_232,
            sourcePID: nil
        )
        let clock = MenuBarItem.fixture(
            tag: .clock,
            windowID: 1_233,
            sourcePID: nil
        )
        let screenCapture = MenuBarItem.fixture(
            tag: .screenCaptureUI,
            windowID: 1_234,
            sourcePID: nil
        )

        XCTAssertTrue(MenuBarSavedLayoutItemPolicy.isLayoutItem(appItem))
        XCTAssertFalse(MenuBarSavedLayoutItemPolicy.isLayoutItem(visibleControl))
        XCTAssertFalse(MenuBarSavedLayoutItemPolicy.isLayoutItem(hiddenControl))
        XCTAssertFalse(MenuBarSavedLayoutItemPolicy.isLayoutItem(clock))
        XCTAssertFalse(MenuBarSavedLayoutItemPolicy.isLayoutItem(screenCapture))
    }

    func testSavedLayoutObservationSnapshotResolvesControlsAndBuildsInitialSequence() throws {
        let visibleItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.visible", title: "Visible"),
            windowID: 1_240,
            bounds: CGRect(x: 700, y: 0, width: 24, height: 22)
        )
        let hiddenItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.hidden", title: "Hidden"),
            windowID: 1_241,
            bounds: CGRect(x: 500, y: 0, width: 24, height: 22)
        )
        let alwaysHiddenItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.alwaysHidden", title: "Always Hidden"),
            windowID: 1_242,
            bounds: CGRect(x: 300, y: 0, width: 24, height: 22)
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_243,
            bounds: CGRect(x: 600, y: 0, width: 32, height: 22),
            sourcePID: nil
        )
        let alwaysHiddenControl = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 1_244,
            bounds: CGRect(x: 400, y: 0, width: 32, height: 22),
            sourcePID: nil
        )

        let snapshot = try XCTUnwrap(
            MenuBarSavedLayoutObservationSnapshot(
                observedItems: [
                    visibleItem,
                    hiddenControl,
                    hiddenItem,
                    alwaysHiddenControl,
                    alwaysHiddenItem,
                ],
                controlItemWindowIDs: MenuBarControlItemWindowIDs(
                    hidden: hiddenControl.windowID,
                    alwaysHidden: alwaysHiddenControl.windowID
                ),
                itemSectionMap: [
                    visibleItem.uniqueIdentifier: MenuBarSection.Name.visible.rawValue,
                    hiddenItem.uniqueIdentifier: MenuBarSection.Name.hidden.rawValue,
                    alwaysHiddenItem.uniqueIdentifier: MenuBarSection.Name.alwaysHidden.rawValue,
                ],
                itemOrder: [
                    MenuBarSection.Name.visible.rawValue: [visibleItem.uniqueIdentifier],
                    MenuBarSection.Name.hidden.rawValue: [hiddenItem.uniqueIdentifier],
                    MenuBarSection.Name.alwaysHidden.rawValue: [alwaysHiddenItem.uniqueIdentifier],
                ],
                makeSectionLookupContext: {
                    MenuBarSectionLookupContext(controlItems: $0) { item in item.bounds }
                }
            )
        )

        XCTAssertEqual(snapshot.controlItems.hidden.uniqueIdentifier, hiddenControl.uniqueIdentifier)
        XCTAssertEqual(snapshot.controlItems.alwaysHidden?.uniqueIdentifier, alwaysHiddenControl.uniqueIdentifier)
        XCTAssertEqual(
            snapshot.items.map(\.uniqueIdentifier),
            [
                visibleItem.uniqueIdentifier,
                hiddenItem.uniqueIdentifier,
                alwaysHiddenItem.uniqueIdentifier,
                hiddenControl.uniqueIdentifier,
                alwaysHiddenControl.uniqueIdentifier,
            ]
        )
        XCTAssertEqual(snapshot.sectionByWindowID[visibleItem.windowID], .visible)
        XCTAssertEqual(snapshot.sectionByWindowID[hiddenItem.windowID], .hidden)
        XCTAssertEqual(snapshot.sectionByWindowID[alwaysHiddenItem.windowID], .alwaysHidden)
        XCTAssertNil(snapshot.sectionByWindowID[hiddenControl.windowID])
        XCTAssertEqual(
            snapshot.sequencePlan.currentFlat,
            [
                visibleItem.uniqueIdentifier,
                hiddenControl.uniqueIdentifier,
                hiddenItem.uniqueIdentifier,
                alwaysHiddenControl.uniqueIdentifier,
                alwaysHiddenItem.uniqueIdentifier,
            ]
        )
        XCTAssertEqual(snapshot.sequencePlan.desiredFiltered, snapshot.sequencePlan.currentFlat)
    }

    func testSavedLayoutObservationSnapshotFailsWhenControlsAreMissing() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.visible", title: "Visible"),
            windowID: 1_250,
            bounds: CGRect(x: 700, y: 0, width: 24, height: 22)
        )

        let snapshot = MenuBarSavedLayoutObservationSnapshot(
            observedItems: [item],
            controlItemWindowIDs: .unresolved,
            itemSectionMap: [item.uniqueIdentifier: MenuBarSection.Name.visible.rawValue],
            itemOrder: [MenuBarSection.Name.visible.rawValue: [item.uniqueIdentifier]],
            makeSectionLookupContext: {
                MenuBarSectionLookupContext(controlItems: $0) { observedItem in observedItem.bounds }
            }
        )

        XCTAssertNil(snapshot)
    }

    func testSavedLayoutRefreshSnapshotRebuildsCurrentFlatFromFreshControls() throws {
        let visibleItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.refresh-visible", title: "Visible"),
            windowID: 1_252,
            bounds: CGRect(x: 700, y: 0, width: 24, height: 22)
        )
        let hiddenItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.refresh-hidden", title: "Hidden"),
            windowID: 1_253,
            bounds: CGRect(x: 500, y: 0, width: 24, height: 22)
        )
        let alwaysHiddenItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.refresh-always-hidden", title: "Always Hidden"),
            windowID: 1_254,
            bounds: CGRect(x: 300, y: 0, width: 24, height: 22)
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_255,
            bounds: CGRect(x: 600, y: 0, width: 32, height: 22),
            sourcePID: nil
        )
        let alwaysHiddenControl = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 1_256,
            bounds: CGRect(x: 400, y: 0, width: 32, height: 22),
            sourcePID: nil
        )

        let snapshot = try XCTUnwrap(
            MenuBarSavedLayoutRefreshSnapshot(
                observedItems: [
                    visibleItem,
                    hiddenControl,
                    hiddenItem,
                    alwaysHiddenControl,
                    alwaysHiddenItem,
                ],
                controlItemWindowIDs: MenuBarControlItemWindowIDs(
                    hidden: hiddenControl.windowID,
                    alwaysHidden: alwaysHiddenControl.windowID
                ),
                hiddenControlUID: hiddenControl.uniqueIdentifier,
                alwaysHiddenControlUID: alwaysHiddenControl.uniqueIdentifier,
                makeSectionLookupContext: {
                    MenuBarSectionLookupContext(controlItems: $0) { item in item.bounds }
                }
            )
        )

        XCTAssertEqual(snapshot.controlItems.hidden.uniqueIdentifier, hiddenControl.uniqueIdentifier)
        XCTAssertEqual(snapshot.controlItems.alwaysHidden?.uniqueIdentifier, alwaysHiddenControl.uniqueIdentifier)
        XCTAssertEqual(
            snapshot.items.map(\.uniqueIdentifier),
            [
                visibleItem.uniqueIdentifier,
                hiddenItem.uniqueIdentifier,
                alwaysHiddenItem.uniqueIdentifier,
            ]
        )
        XCTAssertEqual(snapshot.sectionByWindowID[visibleItem.windowID], .visible)
        XCTAssertEqual(snapshot.sectionByWindowID[hiddenItem.windowID], .hidden)
        XCTAssertEqual(snapshot.sectionByWindowID[alwaysHiddenItem.windowID], .alwaysHidden)
        XCTAssertEqual(
            snapshot.currentFlat,
            [
                visibleItem.uniqueIdentifier,
                hiddenControl.uniqueIdentifier,
                hiddenItem.uniqueIdentifier,
                alwaysHiddenControl.uniqueIdentifier,
                alwaysHiddenItem.uniqueIdentifier,
            ]
        )
    }

    func testSavedLayoutRefreshSnapshotFailsWhenControlsAreMissing() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.refresh-missing", title: "Missing"),
            windowID: 1_257
        )

        let snapshot = MenuBarSavedLayoutRefreshSnapshot(
            observedItems: [item],
            controlItemWindowIDs: .unresolved,
            hiddenControlUID: "hidden-control",
            alwaysHiddenControlUID: nil,
            makeSectionLookupContext: { controlItems in
                MenuBarSectionLookupContext(controlItems: controlItems) { observedItem in observedItem.bounds }
            }
        )

        XCTAssertNil(snapshot)
    }

    func testSavedLayoutCursorSessionBeginsAndFinishesInStableOrder() {
        var events = [String]()
        var watchdog: DispatchTimeInterval?
        var warpedPoint: CGPoint?

        let session = MenuBarSavedLayoutCursorSession.begin(
            mouseLocation: CGPoint(x: 120, y: 200),
            hideCursor: { interval in
                watchdog = interval
                events.append("hide")
            },
            beginSuppression: {
                events.append("begin")
            }
        )

        session.finish(
            screenFrames: [CGRect(x: 0, y: 0, width: 1_440, height: 900)],
            fallbackScreenFrame: nil,
            endSuppression: {
                events.append("end")
            },
            warpCursor: { point in
                warpedPoint = point
                events.append("warp")
            },
            showCursor: {
                events.append("show")
            }
        )

        switch watchdog {
        case .some(.seconds(30)):
            break
        default:
            XCTFail("Expected saved-layout cursor watchdog to be 30 seconds")
        }
        XCTAssertEqual(events, ["hide", "begin", "warp", "end", "show"])
        XCTAssertEqual(warpedPoint, CGPoint(x: 120, y: 700))
    }

    func testSavedLayoutCursorSessionRestorationPointUsesFallbackScreen() {
        let point = MenuBarSavedLayoutCursorSession.restorationPoint(
            for: CGPoint(x: 1_700, y: 100),
            screenFrames: [CGRect(x: 0, y: 0, width: 1_440, height: 900)],
            fallbackScreenFrame: CGRect(x: 1_440, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(point, CGPoint(x: 1_700, y: 800))
    }

    func testSavedLayoutCursorSessionSkipsWarpWhenNoScreenIsAvailable() {
        let point = MenuBarSavedLayoutCursorSession.restorationPoint(
            for: CGPoint(x: 120, y: 200),
            screenFrames: [],
            fallbackScreenFrame: nil
        )

        XCTAssertNil(point)
    }

    func testSavedLayoutPlannedMoveExecutorExecutesMoveAgainstFreshObservation() async throws {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.move", title: "Move"),
            windowID: 1_260,
            bounds: CGRect(x: 500, y: 0, width: 24, height: 22)
        )
        let anchor = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 1_261,
            bounds: CGRect(x: 650, y: 0, width: 24, height: 22)
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_262,
            bounds: CGRect(x: 600, y: 0, width: 32, height: 22),
            sourcePID: nil
        )
        let plannedMove = LayoutSolver.LCSPlannedMove(
            uid: item.uniqueIdentifier,
            destination: .leftOfUID(anchor.uniqueIdentifier)
        )
        var observedContexts = [String]()
        var moved = [(MenuBarItem, MenuBarMoveDestination)]()
        var sleepDurations = [Duration]()

        let outcome = await MenuBarSavedLayoutPlannedMoveExecutor.execute(
            plannedMoves: [plannedMove],
            controlItemWindowIDs: MenuBarControlItemWindowIDs(hidden: hiddenControl.windowID),
            sectionMap: [item.uniqueIdentifier: MenuBarSection.Name.hidden.rawValue],
            observationContext: "lcsMove",
            phase: .lcsMove,
            observeItems: { context in
                observedContexts.append(context)
                return [item, anchor, hiddenControl]
            },
            moveItem: { item, destination in
                moved.append((item, destination))
            },
            recordMoveFailure: { uid, error in
                XCTFail("Unexpected move failure for \(uid): \(error)")
            },
            sleepAfterMove: { duration in
                sleepDurations.append(duration)
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarSavedLayoutPlannedMoveExecutor.Outcome(
                movedCount: 1,
                stopReason: .completed
            )
        )
        XCTAssertFalse(outcome.needsDeferredCacheRefresh)
        XCTAssertEqual(observedContexts, ["lcsMove"])
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(moved.first?.0, item)
        XCTAssertEqual(moved.first?.1, .leftOfItem(anchor))
        XCTAssertEqual(sleepDurations, [MenuBarSavedLayoutExecutionPolicy.delay(after: .lcsMove)])
    }

    func testSavedLayoutPlannedMoveExecutorReportsObservationUnavailable() async {
        let plannedMove = LayoutSolver.LCSPlannedMove(
            uid: "missing",
            destination: .sectionBoundary(.visible)
        )

        let outcome = await MenuBarSavedLayoutPlannedMoveExecutor.execute(
            plannedMoves: [plannedMove],
            controlItemWindowIDs: .unresolved,
            sectionMap: [:],
            observationContext: "lcsMove",
            phase: .lcsMove,
            observeItems: { _ in nil },
            moveItem: { _, _ in
                XCTFail("Move should not run without an observation")
            },
            recordMoveFailure: { uid, error in
                XCTFail("Unexpected move failure for \(uid): \(error)")
            },
            sleepAfterMove: { _ in
                XCTFail("Sleep should not run without a move")
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarSavedLayoutPlannedMoveExecutor.Outcome(
                movedCount: 0,
                stopReason: .observationUnavailable
            )
        )
        XCTAssertTrue(outcome.needsDeferredCacheRefresh)
    }

    func testSavedLayoutPlannedMoveExecutorStopsWhenControlsAreMissing() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.move", title: "Move"),
            windowID: 1_270
        )
        let plannedMove = LayoutSolver.LCSPlannedMove(
            uid: item.uniqueIdentifier,
            destination: .sectionBoundary(.visible)
        )

        let outcome = await MenuBarSavedLayoutPlannedMoveExecutor.execute(
            plannedMoves: [plannedMove],
            controlItemWindowIDs: .unresolved,
            sectionMap: [item.uniqueIdentifier: MenuBarSection.Name.visible.rawValue],
            observationContext: "visibleBoundaryMove",
            phase: .visibleBoundaryMove,
            observeItems: { _ in [item] },
            moveItem: { _, _ in
                XCTFail("Move should not run without resolved control items")
            },
            recordMoveFailure: { uid, error in
                XCTFail("Unexpected move failure for \(uid): \(error)")
            },
            sleepAfterMove: { _ in
                XCTFail("Sleep should not run without a move")
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarSavedLayoutPlannedMoveExecutor.Outcome(
                movedCount: 0,
                stopReason: .controlItemsMissing
            )
        )
        XCTAssertFalse(outcome.needsDeferredCacheRefresh)
    }

    func testSavedLayoutFullSortExecutorExecutesAgainstFreshObservation() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.fullsort", title: "Full Sort"),
            windowID: 1_280
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_281,
            sourcePID: nil
        )
        let controlCenter = MenuBarItem.fixture(
            tag: .controlCenter,
            windowID: 1_282,
            sourcePID: nil
        )
        var observedContexts = [String]()
        var moveStarts = [(String, MenuBarMoveDestination)]()
        var moved = [(MenuBarItem, MenuBarMoveDestination)]()
        var sleepDurations = [Duration]()

        let outcome = await MenuBarSavedLayoutFullSortExecutor.execute(
            sequence: [item.uniqueIdentifier],
            hiddenControlUID: hiddenControl.uniqueIdentifier,
            alwaysHiddenControlUID: nil,
            observationContext: "fullSortMove",
            observeItems: { context in
                observedContexts.append(context)
                return [item, hiddenControl, controlCenter]
            },
            moveItem: { item, destination in
                moved.append((item, destination))
            },
            recordItemMissing: { uid in
                XCTFail("Unexpected missing item: \(uid)")
            },
            recordControlCenterMissing: {
                XCTFail("Control Center should be present")
            },
            recordMoveStart: { uid, destination in
                moveStarts.append((uid, destination))
            },
            recordMoveFailure: { uid, error in
                XCTFail("Unexpected move failure for \(uid): \(error)")
            },
            sleepAfterMove: { duration in
                sleepDurations.append(duration)
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarSavedLayoutFullSortExecutor.Outcome(
                movedCount: 1,
                stopReason: .completed
            )
        )
        XCTAssertFalse(outcome.needsDeferredCacheRefresh)
        XCTAssertEqual(observedContexts, ["fullSortMove"])
        XCTAssertEqual(moveStarts.count, 1)
        XCTAssertEqual(moveStarts.first?.0, item.uniqueIdentifier)
        XCTAssertEqual(moveStarts.first?.1, .leftOfItem(controlCenter))
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(moved.first?.0, item)
        XCTAssertEqual(moved.first?.1, .leftOfItem(controlCenter))
        XCTAssertEqual(sleepDurations, [MenuBarSavedLayoutExecutionPolicy.delay(after: .fullSortMove)])
    }

    func testSavedLayoutFullSortExecutorSkipsMissingItemsAndContinues() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.fullsort", title: "Full Sort"),
            windowID: 1_290
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_291,
            sourcePID: nil
        )
        let controlCenter = MenuBarItem.fixture(
            tag: .controlCenter,
            windowID: 1_292,
            sourcePID: nil
        )
        var missingUIDs = [String]()
        var movedCount = 0

        let outcome = await MenuBarSavedLayoutFullSortExecutor.execute(
            sequence: ["missing", item.uniqueIdentifier],
            hiddenControlUID: hiddenControl.uniqueIdentifier,
            alwaysHiddenControlUID: nil,
            observationContext: "fullSortMove",
            observeItems: { _ in [item, hiddenControl, controlCenter] },
            moveItem: { _, _ in
                movedCount += 1
            },
            recordItemMissing: { uid in
                missingUIDs.append(uid)
            },
            recordControlCenterMissing: {
                XCTFail("Control Center should be present")
            },
            recordMoveStart: { _, _ in },
            recordMoveFailure: { uid, error in
                XCTFail("Unexpected move failure for \(uid): \(error)")
            },
            sleepAfterMove: { _ in }
        )

        XCTAssertEqual(missingUIDs, ["missing"])
        XCTAssertEqual(movedCount, 1)
        XCTAssertEqual(
            outcome,
            MenuBarSavedLayoutFullSortExecutor.Outcome(
                movedCount: 1,
                stopReason: .completed
            )
        )
    }

    func testSavedLayoutFullSortExecutorReportsObservationUnavailable() async {
        let outcome = await MenuBarSavedLayoutFullSortExecutor.execute(
            sequence: ["missing"],
            hiddenControlUID: "hidden",
            alwaysHiddenControlUID: nil,
            observationContext: "fullSortMove",
            observeItems: { _ in nil },
            moveItem: { _, _ in
                XCTFail("Move should not run without an observation")
            },
            recordItemMissing: { uid in
                XCTFail("Missing callback should not run without observation: \(uid)")
            },
            recordControlCenterMissing: {
                XCTFail("Control Center callback should not run without observation")
            },
            recordMoveStart: { uid, _ in
                XCTFail("Move start should not run without observation: \(uid)")
            },
            recordMoveFailure: { uid, error in
                XCTFail("Unexpected move failure for \(uid): \(error)")
            },
            sleepAfterMove: { _ in
                XCTFail("Sleep should not run without a move")
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarSavedLayoutFullSortExecutor.Outcome(
                movedCount: 0,
                stopReason: .observationUnavailable
            )
        )
        XCTAssertTrue(outcome.needsDeferredCacheRefresh)
    }

    func testSavedLayoutFullSortExecutorStopsWhenControlCenterIsMissing() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.fullsort", title: "Full Sort"),
            windowID: 1_300
        )
        var recordedControlCenterMissing = false

        let outcome = await MenuBarSavedLayoutFullSortExecutor.execute(
            sequence: [item.uniqueIdentifier],
            hiddenControlUID: "hidden",
            alwaysHiddenControlUID: nil,
            observationContext: "fullSortMove",
            observeItems: { _ in [item] },
            moveItem: { _, _ in
                XCTFail("Move should not run without Control Center")
            },
            recordItemMissing: { uid in
                XCTFail("Item should be present: \(uid)")
            },
            recordControlCenterMissing: {
                recordedControlCenterMissing = true
            },
            recordMoveStart: { uid, _ in
                XCTFail("Move start should not run without Control Center: \(uid)")
            },
            recordMoveFailure: { uid, error in
                XCTFail("Unexpected move failure for \(uid): \(error)")
            },
            sleepAfterMove: { _ in
                XCTFail("Sleep should not run without a move")
            }
        )

        XCTAssertTrue(recordedControlCenterMissing)
        XCTAssertEqual(
            outcome,
            MenuBarSavedLayoutFullSortExecutor.Outcome(
                movedCount: 0,
                stopReason: .controlCenterMissing
            )
        )
        XCTAssertFalse(outcome.needsDeferredCacheRefresh)
    }

    func testSavedLayoutSectionTransitionExecutorMovesControlAndFallbackItems() async {
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_310,
            bounds: CGRect(x: 600, y: 0, width: 32, height: 22),
            sourcePID: nil
        )
        let alwaysHiddenControl = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 1_311,
            bounds: CGRect(x: 400, y: 0, width: 32, height: 22),
            sourcePID: nil
        )
        let hiddenItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.hidden-transition", title: "Hidden"),
            windowID: 1_312,
            bounds: CGRect(x: 300, y: 0, width: 24, height: 22)
        )
        let alwaysHiddenItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.always-hidden-transition", title: "Always Hidden"),
            windowID: 1_313,
            bounds: CGRect(x: 500, y: 0, width: 24, height: 22)
        )
        let itemOrder = [
            MenuBarSection.Name.hidden.rawValue: [hiddenItem.uniqueIdentifier],
            MenuBarSection.Name.alwaysHidden.rawValue: [alwaysHiddenItem.uniqueIdentifier],
        ]
        let plan = MenuBarSectionTransitionPolicy.AlwaysHiddenControlMovePlan(
            controlUID: alwaysHiddenControl.uniqueIdentifier,
            anchorCandidates: [hiddenControl.uniqueIdentifier]
        )
        let observedItems = [alwaysHiddenControl, hiddenControl, hiddenItem, alwaysHiddenItem]
        var observedContexts = [String]()
        var moved = [(MenuBarItem, MenuBarMoveDestination)]()
        var fallbackPlans = [MenuBarSectionTransitionPolicy.FallbackPlan]()
        var sleepDurations = [Duration]()

        let outcome = await MenuBarSectionTransitionExecutor.execute(
            plan: plan,
            itemOrder: itemOrder,
            hiddenControlUID: hiddenControl.uniqueIdentifier,
            controlItemWindowIDs: MenuBarControlItemWindowIDs(
                hidden: hiddenControl.windowID,
                alwaysHidden: alwaysHiddenControl.windowID
            ),
            observeItems: { context in
                observedContexts.append(context)
                return observedItems
            },
            makeSectionLookupContext: {
                MenuBarSectionLookupContext(controlItems: $0) { item in item.bounds }
            },
            moveItem: { item, destination in
                moved.append((item, destination))
            },
            recordControlMoveStart: { _ in },
            recordControlMoveFailure: { error in
                XCTFail("Unexpected control move failure: \(error)")
            },
            recordFallbackPlan: { fallbackPlan in
                fallbackPlans.append(fallbackPlan)
            },
            recordFallbackMoveFailure: { fallbackMove, error in
                XCTFail("Unexpected fallback move failure for \(fallbackMove.uniqueIdentifier): \(error)")
            },
            sleepAfterMove: { duration in
                sleepDurations.append(duration)
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarSectionTransitionExecutor.Outcome(
                movedCount: 3,
                stopReason: .completed
            )
        )
        XCTAssertFalse(outcome.needsDeferredCacheRefresh)
        XCTAssertEqual(observedContexts, ["alwaysHiddenControlMove", "crossSectionFallback"])
        XCTAssertEqual(moved.count, 3)
        XCTAssertEqual(moved[0].0, alwaysHiddenControl)
        XCTAssertEqual(moved[0].1, .leftOfItem(hiddenControl))
        XCTAssertEqual(moved[1].0, alwaysHiddenItem)
        XCTAssertEqual(moved[1].1, .leftOfItem(alwaysHiddenControl))
        XCTAssertEqual(moved[2].0, hiddenItem)
        XCTAssertEqual(moved[2].1, .rightOfItem(alwaysHiddenControl))
        XCTAssertEqual(fallbackPlans.count, 1)
        XCTAssertEqual(fallbackPlans.first?.toAlwaysHidden, [alwaysHiddenItem.uniqueIdentifier])
        XCTAssertEqual(fallbackPlans.first?.toHidden, [hiddenItem.uniqueIdentifier])
        XCTAssertEqual(
            sleepDurations,
            [
                MenuBarSavedLayoutExecutionPolicy.delay(after: .controlBoundaryMove),
                MenuBarSavedLayoutExecutionPolicy.delay(after: .crossSectionFallbackMove),
                MenuBarSavedLayoutExecutionPolicy.delay(after: .crossSectionFallbackMove),
            ]
        )
    }

    func testSavedLayoutSectionTransitionExecutorReportsObservationUnavailableBeforeControlMove() async {
        let plan = MenuBarSectionTransitionPolicy.AlwaysHiddenControlMovePlan(
            controlUID: "always-hidden-control",
            anchorCandidates: ["hidden-control"]
        )

        let outcome = await MenuBarSectionTransitionExecutor.execute(
            plan: plan,
            itemOrder: [:],
            hiddenControlUID: "hidden-control",
            controlItemWindowIDs: .unresolved,
            observeItems: { _ in nil },
            makeSectionLookupContext: { controlItems in
                MenuBarSectionLookupContext(controlItems: controlItems) { item in item.bounds }
            },
            moveItem: { _, _ in
                XCTFail("Move should not run without an observation")
            },
            recordControlMoveStart: { _ in
                XCTFail("Move start should not run without an observation")
            },
            recordControlMoveFailure: { error in
                XCTFail("Unexpected control move failure: \(error)")
            },
            recordFallbackPlan: { _ in
                XCTFail("Fallback plan should not run without an observation")
            },
            recordFallbackMoveFailure: { fallbackMove, error in
                XCTFail("Unexpected fallback move failure for \(fallbackMove.uniqueIdentifier): \(error)")
            },
            sleepAfterMove: { _ in
                XCTFail("Sleep should not run without a move")
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarSectionTransitionExecutor.Outcome(
                movedCount: 0,
                stopReason: .observationUnavailable
            )
        )
        XCTAssertTrue(outcome.needsDeferredCacheRefresh)
    }

    func testSavedLayoutSectionTransitionExecutorReportsObservationUnavailableBeforeFallback() async {
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_320,
            sourcePID: nil
        )
        let alwaysHiddenControl = MenuBarItem.fixture(
            tag: .alwaysHiddenControlItem,
            windowID: 1_321,
            sourcePID: nil
        )
        let plan = MenuBarSectionTransitionPolicy.AlwaysHiddenControlMovePlan(
            controlUID: alwaysHiddenControl.uniqueIdentifier,
            anchorCandidates: [hiddenControl.uniqueIdentifier]
        )
        var observedContexts = [String]()
        var moved = [(MenuBarItem, MenuBarMoveDestination)]()
        var sleepDurations = [Duration]()

        let outcome = await MenuBarSectionTransitionExecutor.execute(
            plan: plan,
            itemOrder: [:],
            hiddenControlUID: hiddenControl.uniqueIdentifier,
            controlItemWindowIDs: MenuBarControlItemWindowIDs(
                hidden: hiddenControl.windowID,
                alwaysHidden: alwaysHiddenControl.windowID
            ),
            observeItems: { context in
                observedContexts.append(context)
                if context == "alwaysHiddenControlMove" {
                    return [alwaysHiddenControl, hiddenControl]
                }
                return nil
            },
            makeSectionLookupContext: { controlItems in
                MenuBarSectionLookupContext(controlItems: controlItems) { item in item.bounds }
            },
            moveItem: { item, destination in
                moved.append((item, destination))
            },
            recordControlMoveStart: { _ in },
            recordControlMoveFailure: { error in
                XCTFail("Unexpected control move failure: \(error)")
            },
            recordFallbackPlan: { _ in
                XCTFail("Fallback plan should not run without fallback observation")
            },
            recordFallbackMoveFailure: { fallbackMove, error in
                XCTFail("Unexpected fallback move failure for \(fallbackMove.uniqueIdentifier): \(error)")
            },
            sleepAfterMove: { duration in
                sleepDurations.append(duration)
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarSectionTransitionExecutor.Outcome(
                movedCount: 1,
                stopReason: .observationUnavailable
            )
        )
        XCTAssertTrue(outcome.needsDeferredCacheRefresh)
        XCTAssertEqual(observedContexts, ["alwaysHiddenControlMove", "crossSectionFallback"])
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(moved.first?.0, alwaysHiddenControl)
        XCTAssertEqual(moved.first?.1, .leftOfItem(hiddenControl))
        XCTAssertEqual(sleepDurations, [MenuBarSavedLayoutExecutionPolicy.delay(after: .controlBoundaryMove)])
    }

    func testSavedLayoutLCSExecutorMovesVisibleBoundaryAndSkipsItemReorder() async {
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_330,
            bounds: CGRect(x: 600, y: 0, width: 32, height: 22),
            sourcePID: nil
        )
        let hiddenItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.lcs-visible", title: "Visible"),
            windowID: 1_331,
            bounds: CGRect(x: 500, y: 0, width: 24, height: 22)
        )
        let visibleItem = MenuBarItem.fixture(
            tag: hiddenItem.tag,
            windowID: hiddenItem.windowID,
            bounds: CGRect(x: 700, y: 0, width: 24, height: 22)
        )
        var observedContexts = [String]()
        var moved = [(MenuBarItem, MenuBarMoveDestination)]()
        var visibleBoundaryMoveCounts = [Int]()
        var noReorderMoveCounts = [Int]()
        var completions = [Int]()

        let outcome = await MenuBarSavedLayoutLCSExecutor.execute(
            currentFlat: [hiddenControl.uniqueIdentifier, hiddenItem.uniqueIdentifier],
            items: [hiddenItem, hiddenControl],
            sectionByWindowID: [hiddenItem.windowID: .hidden],
            desiredFiltered: [hiddenItem.uniqueIdentifier, hiddenControl.uniqueIdentifier],
            sectionMap: [hiddenItem.uniqueIdentifier: MenuBarSection.Name.visible.rawValue],
            itemOrder: [MenuBarSection.Name.visible.rawValue: [hiddenItem.uniqueIdentifier]],
            hiddenControlUID: hiddenControl.uniqueIdentifier,
            alwaysHiddenControlUID: nil,
            controlItemWindowIDs: MenuBarControlItemWindowIDs(hidden: hiddenControl.windowID),
            observeItems: { context in
                observedContexts.append(context)
                switch context {
                case "visibleBoundaryMove":
                    return [hiddenItem, hiddenControl]
                case "afterVisibleBoundaryMoves", "afterControlBoundaryMoves":
                    return [visibleItem, hiddenControl]
                default:
                    XCTFail("Unexpected observation context: \(context)")
                    return nil
                }
            },
            makeSectionLookupContext: {
                MenuBarSectionLookupContext(controlItems: $0) { item in item.bounds }
            },
            moveItem: { item, destination in
                moved.append((item, destination))
            },
            recordVisibleBoundaryMovesNeeded: { count in
                visibleBoundaryMoveCounts.append(count)
            },
            recordNoItemReorderingNeeded: { movedCount in
                noReorderMoveCounts.append(movedCount)
            },
            recordCompletion: { movedCount in
                completions.append(movedCount)
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarSavedLayoutLCSExecutor.Outcome(
                movedCount: 1,
                plannedItemMoveCount: 0,
                stopReason: .completed
            )
        )
        XCTAssertFalse(outcome.needsDeferredCacheRefresh)
        XCTAssertEqual(
            observedContexts,
            ["visibleBoundaryMove", "afterVisibleBoundaryMoves", "afterControlBoundaryMoves"]
        )
        XCTAssertEqual(visibleBoundaryMoveCounts, [1])
        XCTAssertEqual(noReorderMoveCounts, [1])
        XCTAssertTrue(completions.isEmpty)
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(moved.first?.0, hiddenItem)
        guard case let .rightOfItem(anchor)? = moved.first?.1 else {
            XCTFail("Expected visible boundary move to target the hidden control")
            return
        }
        XCTAssertEqual(anchor.uniqueIdentifier, hiddenControl.uniqueIdentifier)
    }

    func testSavedLayoutLCSExecutorRunsItemReorderAgainstFreshObservation() async {
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_340,
            sourcePID: nil
        )
        let first = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.lcs-first", title: "First"),
            windowID: 1_341
        )
        let second = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.lcs-second", title: "Second"),
            windowID: 1_342
        )
        var observedContexts = [String]()
        var moved = [(MenuBarItem, MenuBarMoveDestination)]()
        var itemMovePlans = [(Int, Int)]()
        var completions = [Int]()

        let outcome = await MenuBarSavedLayoutLCSExecutor.execute(
            currentFlat: [
                hiddenControl.uniqueIdentifier,
                first.uniqueIdentifier,
                second.uniqueIdentifier,
            ],
            items: [first, second, hiddenControl],
            sectionByWindowID: [
                first.windowID: .hidden,
                second.windowID: .hidden,
            ],
            desiredFiltered: [
                hiddenControl.uniqueIdentifier,
                second.uniqueIdentifier,
                first.uniqueIdentifier,
            ],
            sectionMap: [
                first.uniqueIdentifier: MenuBarSection.Name.hidden.rawValue,
                second.uniqueIdentifier: MenuBarSection.Name.hidden.rawValue,
            ],
            itemOrder: [
                MenuBarSection.Name.hidden.rawValue: [
                    second.uniqueIdentifier,
                    first.uniqueIdentifier,
                ],
            ],
            hiddenControlUID: hiddenControl.uniqueIdentifier,
            alwaysHiddenControlUID: nil,
            controlItemWindowIDs: MenuBarControlItemWindowIDs(hidden: hiddenControl.windowID),
            observeItems: { context in
                observedContexts.append(context)
                if context == "lcsMove" {
                    return [first, second, hiddenControl]
                }
                XCTFail("Unexpected observation context: \(context)")
                return nil
            },
            makeSectionLookupContext: {
                MenuBarSectionLookupContext(controlItems: $0) { item in item.bounds }
            },
            moveItem: { item, destination in
                moved.append((item, destination))
            },
            recordItemMovesNeeded: { plannedCount, movedCount in
                itemMovePlans.append((plannedCount, movedCount))
            },
            recordCompletion: { movedCount in
                completions.append(movedCount)
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarSavedLayoutLCSExecutor.Outcome(
                movedCount: 1,
                plannedItemMoveCount: 1,
                stopReason: .completed
            )
        )
        XCTAssertEqual(observedContexts, ["lcsMove"])
        XCTAssertEqual(itemMovePlans.count, 1)
        XCTAssertEqual(itemMovePlans.first?.0, 1)
        XCTAssertEqual(itemMovePlans.first?.1, 0)
        XCTAssertEqual(completions, [1])
        XCTAssertEqual(moved.count, 1)
    }

    func testSavedLayoutLCSExecutorDefersWhenRefreshLosesControlItems() async {
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_350,
            bounds: CGRect(x: 600, y: 0, width: 32, height: 22),
            sourcePID: nil
        )
        let hiddenItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.lcs-missing-control", title: "Missing Control"),
            windowID: 1_351,
            bounds: CGRect(x: 500, y: 0, width: 24, height: 22)
        )
        let visibleItem = MenuBarItem.fixture(
            tag: hiddenItem.tag,
            windowID: hiddenItem.windowID,
            bounds: CGRect(x: 700, y: 0, width: 24, height: 22)
        )
        var observedContexts = [String]()
        var missingControlContexts = [String]()

        let outcome = await MenuBarSavedLayoutLCSExecutor.execute(
            currentFlat: [hiddenControl.uniqueIdentifier, hiddenItem.uniqueIdentifier],
            items: [hiddenItem, hiddenControl],
            sectionByWindowID: [hiddenItem.windowID: .hidden],
            desiredFiltered: [hiddenItem.uniqueIdentifier, hiddenControl.uniqueIdentifier],
            sectionMap: [hiddenItem.uniqueIdentifier: MenuBarSection.Name.visible.rawValue],
            itemOrder: [MenuBarSection.Name.visible.rawValue: [hiddenItem.uniqueIdentifier]],
            hiddenControlUID: hiddenControl.uniqueIdentifier,
            alwaysHiddenControlUID: nil,
            controlItemWindowIDs: MenuBarControlItemWindowIDs(hidden: hiddenControl.windowID),
            observeItems: { context in
                observedContexts.append(context)
                if context == "visibleBoundaryMove" {
                    return [hiddenItem, hiddenControl]
                }
                if context == "afterVisibleBoundaryMoves" {
                    return [visibleItem]
                }
                XCTFail("Unexpected observation context: \(context)")
                return nil
            },
            makeSectionLookupContext: {
                MenuBarSectionLookupContext(controlItems: $0) { item in item.bounds }
            },
            moveItem: { _, _ in },
            recordRefreshControlItemsMissing: { context in
                missingControlContexts.append(context)
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarSavedLayoutLCSExecutor.Outcome(
                movedCount: 1,
                plannedItemMoveCount: 0,
                stopReason: .controlItemsMissing
            )
        )
        XCTAssertTrue(outcome.needsDeferredCacheRefresh)
        XCTAssertEqual(observedContexts, ["visibleBoundaryMove", "afterVisibleBoundaryMoves"])
        XCTAssertEqual(missingControlContexts, ["afterVisibleBoundaryMoves"])
    }

    func testSavedLayoutExecutionPolicyChoosesFullSortOnlyForNotchedDisplayWhenLCSDisabled() {
        XCTAssertEqual(
            MenuBarSavedLayoutExecutionPolicy.strategy(
                displayHasNotch: true,
                useLCSOnNotchedDisplay: false
            ),
            .fullSort
        )
        XCTAssertEqual(
            MenuBarSavedLayoutExecutionPolicy.strategy(
                displayHasNotch: true,
                useLCSOnNotchedDisplay: true
            ),
            .lcs
        )
        XCTAssertEqual(
            MenuBarSavedLayoutExecutionPolicy.strategy(
                displayHasNotch: false,
                useLCSOnNotchedDisplay: false
            ),
            .lcs
        )
    }

    func testSavedLayoutExecutionPolicyInitialPlanSkipsWhenCurrentMatches() {
        let hiddenControl = "continuum:HiddenControlItem"
        let alwaysHiddenControl = "continuum:AlwaysHiddenControlItem"
        let desired = ["visible", hiddenControl, "hidden", alwaysHiddenControl, "ah"]

        let plan = MenuBarSavedLayoutExecutionPolicy.initialPlan(
            currentFlat: ["unmanaged", "visible", hiddenControl, "hidden", alwaysHiddenControl, "ah"],
            desiredFiltered: desired,
            sectionMap: [
                "visible": "visible",
                "hidden": "hidden",
                "ah": "alwaysHidden",
            ],
            hiddenControlUID: hiddenControl,
            alwaysHiddenControlUID: alwaysHiddenControl,
            strategy: .fullSort
        )

        XCTAssertEqual(plan, .alreadyMatches)
    }

    func testSavedLayoutExecutionPolicyInitialPlanBuildsFullSortSequence() {
        let hiddenControl = "continuum:HiddenControlItem"
        let alwaysHiddenControl = "continuum:AlwaysHiddenControlItem"

        let plan = MenuBarSavedLayoutExecutionPolicy.initialPlan(
            currentFlat: ["visible", hiddenControl, "hidden", alwaysHiddenControl, "ah"],
            desiredFiltered: ["visible", hiddenControl, "hidden", alwaysHiddenControl, "ah"],
            sectionMap: [
                "visible": "visible",
                "hidden": "hidden",
                "ah": "alwaysHidden",
            ],
            hiddenControlUID: hiddenControl,
            alwaysHiddenControlUID: alwaysHiddenControl,
            strategy: .fullSort
        )

        XCTAssertEqual(plan, .alreadyMatches)

        let changedPlan = MenuBarSavedLayoutExecutionPolicy.initialPlan(
            currentFlat: ["hidden", hiddenControl, "visible", alwaysHiddenControl, "ah"],
            desiredFiltered: ["visible", hiddenControl, "hidden", alwaysHiddenControl, "ah"],
            sectionMap: [
                "visible": "visible",
                "hidden": "hidden",
                "ah": "alwaysHidden",
            ],
            hiddenControlUID: hiddenControl,
            alwaysHiddenControlUID: alwaysHiddenControl,
            strategy: .fullSort
        )

        XCTAssertEqual(
            changedPlan,
            .fullSort(sequence: ["ah", alwaysHiddenControl, "hidden", hiddenControl, "visible"])
        )
    }

    func testSavedLayoutExecutionPolicyInitialPlanKeepsLCSStrategy() {
        let plan = MenuBarSavedLayoutExecutionPolicy.initialPlan(
            currentFlat: ["b", "a"],
            desiredFiltered: ["a", "b"],
            sectionMap: [
                "a": "visible",
                "b": "visible",
            ],
            hiddenControlUID: "hidden",
            alwaysHiddenControlUID: nil,
            strategy: .lcs
        )

        XCTAssertEqual(plan, .lcs)
    }

    func testSavedLayoutExecutionPolicyLCSMovePlanStripsControls() {
        let hiddenControl = "continuum:HiddenControlItem"
        let alwaysHiddenControl = "continuum:AlwaysHiddenControlItem"

        let moves = MenuBarSavedLayoutExecutionPolicy.lcsMovePlan(
            currentFlat: ["b", hiddenControl, "a", alwaysHiddenControl, "c"],
            desiredFiltered: ["a", hiddenControl, "b", alwaysHiddenControl, "c"],
            sectionMap: [
                "a": "visible",
                "b": "visible",
                "c": "visible",
            ],
            hiddenControlUID: hiddenControl,
            alwaysHiddenControlUID: alwaysHiddenControl
        )

        XCTAssertEqual(moves, [
            LayoutSolver.LCSPlannedMove(uid: "b", destination: .leftOfUID("c")),
        ])
    }

    func testSavedLayoutExecutionPolicyPlansVisibleBoundaryMoves() {
        let hiddenControl = "continuum:HiddenControlItem"
        let alwaysHiddenControl = "continuum:AlwaysHiddenControlItem"

        let moves = MenuBarSavedLayoutExecutionPolicy.visibleBoundaryMovePlan(
            items: [
                savedLayoutSectionItem("a", currentSection: .visible),
                savedLayoutSectionItem("b", currentSection: .hidden),
                savedLayoutSectionItem("non-layout", currentSection: .visible, isLayoutItem: false),
            ],
            desiredFiltered: ["a", "b", hiddenControl, "non-layout", alwaysHiddenControl],
            sectionMap: [
                "a": "visible",
                "b": "visible",
                "non-layout": "hidden",
            ],
            hiddenControlUID: hiddenControl,
            alwaysHiddenControlUID: alwaysHiddenControl
        )

        XCTAssertEqual(moves, [
            LayoutSolver.LCSPlannedMove(uid: "b", destination: .sectionBoundary(.visible)),
        ])
    }

    func testSavedLayoutExecutionPolicyResolvesFullSortMoveAgainstFreshControlCenter() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status", title: "Status"),
            windowID: 217
        )
        let controlCenter = MenuBarItem.fixture(tag: .controlCenter, windowID: 218)

        let resolution = MenuBarSavedLayoutExecutionPolicy.fullSortMoveResolution(
            uid: item.uniqueIdentifier,
            items: [item, controlCenter],
            hiddenControlUID: "continuum:HiddenControlItem",
            alwaysHiddenControlUID: nil,
            isLayoutItem: { $0.canBeHidden }
        )

        XCTAssertEqual(
            resolution,
            .move(
                MenuBarSavedLayoutExecutionPolicy.ResolvedMove(
                    item: item,
                    destination: .leftOfItem(controlCenter)
                )
            )
        )
    }

    func testSavedLayoutExecutionPolicyFullSortResolutionReportsMissingInputs() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status", title: "Status"),
            windowID: 219
        )
        let controlCenter = MenuBarItem.fixture(tag: .controlCenter, windowID: 220)

        XCTAssertEqual(
            MenuBarSavedLayoutExecutionPolicy.fullSortMoveResolution(
                uid: "missing",
                items: [controlCenter],
                hiddenControlUID: "continuum:HiddenControlItem",
                alwaysHiddenControlUID: nil,
                isLayoutItem: { $0.canBeHidden }
            ),
            .itemMissing
        )
        XCTAssertEqual(
            MenuBarSavedLayoutExecutionPolicy.fullSortMoveResolution(
                uid: item.uniqueIdentifier,
                items: [item],
                hiddenControlUID: "continuum:HiddenControlItem",
                alwaysHiddenControlUID: nil,
                isLayoutItem: { $0.canBeHidden }
            ),
            .controlCenterMissing
        )
    }

    func testSavedLayoutExecutionPolicyResolvesPlannedMoveWithSectionFallback() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.status", title: "Status"),
            windowID: 221
        )
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
        let planned = LayoutSolver.LCSPlannedMove(
            uid: item.uniqueIdentifier,
            destination: .leftOfUID("missing-anchor")
        )

        let resolution = MenuBarSavedLayoutExecutionPolicy.plannedMoveResolution(
            planned: planned,
            items: [item],
            controlItems: controlItems,
            fallbackSection: .hidden,
            isLayoutItem: { $0.canBeHidden }
        )

        XCTAssertEqual(
            resolution,
            .move(
                MenuBarSavedLayoutExecutionPolicy.ResolvedMove(
                    item: item,
                    destination: .leftOfItem(controlItems.hidden)
                )
            )
        )
    }

    func testSavedLayoutExecutionPolicyPlannedMoveResolutionSkipsMissingItem() {
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
        let planned = LayoutSolver.LCSPlannedMove(
            uid: "missing",
            destination: .sectionBoundary(.hidden)
        )

        let resolution = MenuBarSavedLayoutExecutionPolicy.plannedMoveResolution(
            planned: planned,
            items: [],
            controlItems: controlItems,
            fallbackSection: .hidden,
            isLayoutItem: { $0.canBeHidden }
        )

        XCTAssertEqual(resolution, .itemMissing)
    }

    func testSavedLayoutSequencePolicySnapshotsSectionsByWindowID() {
        let first = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.shared", title: "Shared"),
            windowID: 222
        )
        let ignored = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.ignored", title: "Ignored"),
            windowID: 223
        )
        let second = MenuBarItem.fixture(
            tag: first.tag,
            windowID: 224
        )

        let snapshot = MenuBarSavedLayoutSequencePolicy.sectionSnapshot(
            items: [first, ignored, second],
            isLayoutItem: { $0.windowID != ignored.windowID },
            sectionForItem: { item in
                switch item.windowID {
                case first.windowID:
                    .hidden
                case second.windowID:
                    .alwaysHidden
                default:
                    .visible
                }
            }
        )

        XCTAssertEqual(snapshot, [
            first.windowID: .hidden,
            second.windowID: .alwaysHidden,
        ])
    }

    func testSavedLayoutSequencePolicyBuildsItemObservationsFromSnapshot() {
        let visible = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.visible", title: "Visible"),
            windowID: 225
        )
        let ignored = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.ignored", title: "Ignored"),
            windowID: 226
        )
        let sectionByWindowID: [CGWindowID: MenuBarSection.Name] = [
            visible.windowID: .visible,
        ]

        let observations = MenuBarSavedLayoutSequencePolicy.itemObservations(
            items: [visible, ignored],
            sectionByWindowID: sectionByWindowID,
            isLayoutItem: { $0.windowID == visible.windowID }
        )

        XCTAssertEqual(observations, [
            MenuBarSavedLayoutSequencePolicy.ItemObservation(
                uniqueIdentifier: visible.uniqueIdentifier,
                currentSection: .visible,
                isLayoutItem: true
            ),
            MenuBarSavedLayoutSequencePolicy.ItemObservation(
                uniqueIdentifier: ignored.uniqueIdentifier,
                currentSection: nil,
                isLayoutItem: false
            ),
        ])
    }

    func testSavedLayoutSequencePolicyBuildsCurrentAndDesiredSequencesWithControls() {
        let hiddenControl = "continuum:HiddenControlItem"
        let alwaysHiddenControl = "continuum:AlwaysHiddenControlItem"

        let plan = MenuBarSavedLayoutSequencePolicy.plan(
            items: [
                savedLayoutSequenceItem("hidden", currentSection: .hidden),
                savedLayoutSequenceItem("visible", currentSection: .visible),
                savedLayoutSequenceItem("ah", currentSection: .alwaysHidden),
                savedLayoutSequenceItem(hiddenControl, currentSection: .hidden),
                savedLayoutSequenceItem(alwaysHiddenControl, currentSection: .alwaysHidden),
                savedLayoutSequenceItem("ignored", currentSection: .visible, isLayoutItem: false),
            ],
            itemSectionMap: [
                "visible": "visible",
                "missing": "visible",
                "hidden": "hidden",
                "ah": "alwaysHidden",
            ],
            itemOrder: [
                "visible": ["visible", "missing"],
                "hidden": ["hidden"],
                "alwaysHidden": ["ah"],
            ],
            hiddenControlUID: hiddenControl,
            alwaysHiddenControlUID: alwaysHiddenControl
        )

        XCTAssertEqual(plan.currentFlat, ["visible", hiddenControl, "hidden", alwaysHiddenControl, "ah"])
        XCTAssertEqual(plan.desiredFlat, ["visible", "missing", hiddenControl, "hidden", alwaysHiddenControl, "ah"])
        XCTAssertEqual(plan.desiredFiltered, ["visible", hiddenControl, "hidden", alwaysHiddenControl, "ah"])
        XCTAssertEqual(plan.sectionUIDs[.visible], ["visible"])
        XCTAssertEqual(plan.sectionUIDs[.hidden], ["hidden"])
        XCTAssertEqual(plan.sectionUIDs[.alwaysHidden], ["ah"])
        XCTAssertEqual(plan.sectionMap[hiddenControl], "hidden")
        XCTAssertEqual(plan.sectionMap[alwaysHiddenControl], "alwaysHidden")
    }

    func testSavedLayoutSequencePolicyOmitsMissingAlwaysHiddenControl() {
        let hiddenControl = "continuum:HiddenControlItem"

        let plan = MenuBarSavedLayoutSequencePolicy.plan(
            items: [
                savedLayoutSequenceItem("visible", currentSection: .visible),
                savedLayoutSequenceItem("ah", currentSection: .alwaysHidden),
            ],
            itemSectionMap: [
                "visible": "visible",
                "ah": "alwaysHidden",
            ],
            itemOrder: [
                "visible": ["visible"],
                "alwaysHidden": ["ah"],
            ],
            hiddenControlUID: hiddenControl,
            alwaysHiddenControlUID: nil
        )

        XCTAssertEqual(plan.currentFlat, ["visible", hiddenControl, "ah"])
        XCTAssertEqual(plan.desiredFlat, ["visible", hiddenControl, "ah"])
        XCTAssertEqual(plan.desiredFiltered, ["visible", hiddenControl, "ah"])
        XCTAssertNil(plan.sectionMap["continuum:AlwaysHiddenControlItem"])
    }

    func testSavedLayoutExecutionPolicyPinsMovePacingByPhase() {
        XCTAssertEqual(
            MenuBarSavedLayoutExecutionPolicy.delay(after: .fullSortMove),
            .milliseconds(200)
        )
        XCTAssertEqual(
            MenuBarSavedLayoutExecutionPolicy.delay(after: .visibleBoundaryMove),
            .milliseconds(150)
        )
        XCTAssertEqual(
            MenuBarSavedLayoutExecutionPolicy.delay(after: .crossSectionFallbackMove),
            .milliseconds(100)
        )
        XCTAssertEqual(
            MenuBarSavedLayoutExecutionPolicy.delay(after: .lcsMove),
            .milliseconds(200)
        )
    }

    func testSavedLayoutPreparationBuildsAlreadyMatchingPlan() throws {
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 9_001,
            bounds: CGRect(x: 400, y: 0, width: 10, height: 22),
            sourcePID: nil
        )
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.saved", title: "Saved"),
            windowID: 9_002,
            bounds: CGRect(x: 500, y: 0, width: 24, height: 22)
        )
        let snapshot = try XCTUnwrap(
            savedLayoutPreparationSnapshot(
                observedItems: [item, hiddenControl],
                itemSectionMap: [item.uniqueIdentifier: MenuBarSection.Name.visible.rawValue],
                itemOrder: [
                    MenuBarSection.Name.visible.rawValue: [item.uniqueIdentifier],
                ]
            )
        )

        let plan = MenuBarSavedLayoutPreparation.prepare(
            observationSnapshot: snapshot,
            savedSectionOrder: [
                MenuBarSection.Name.visible.rawValue: [item.uniqueIdentifier],
            ],
            newItemsPlacement: newItemsPlacement(section: MenuBarSection.Name.hidden.rawValue),
            settings: MenuBarSavedLayoutPreparation.Settings(
                enableMenuBarItemOverflow: false,
                useLCSOnNotchedDisplay: false
            ),
            screen: nil,
            notchGap: MenuBarSection.notchGap
        )

        XCTAssertEqual(plan.currentFlat, [item.uniqueIdentifier, hiddenControl.uniqueIdentifier])
        XCTAssertEqual(plan.desiredFiltered, [item.uniqueIdentifier, hiddenControl.uniqueIdentifier])
        XCTAssertEqual(plan.executionPlan, .alreadyMatches)
        XCTAssertFalse(plan.unmanagedPlan.hasUnmanagedItems)
        XCTAssertNil(plan.notchOverflow)
    }

    func testSavedLayoutPreparationPlacesUnmanagedItemsBeforeExecutionPlanning() throws {
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 9_011,
            bounds: CGRect(x: 400, y: 0, width: 10, height: 22),
            sourcePID: nil
        )
        let saved = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.saved", title: "Saved"),
            windowID: 9_012,
            bounds: CGRect(x: 520, y: 0, width: 24, height: 22)
        )
        let unmanaged = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.new", title: "New"),
            windowID: 9_013,
            bounds: CGRect(x: 560, y: 0, width: 24, height: 22)
        )
        let snapshot = try XCTUnwrap(
            savedLayoutPreparationSnapshot(
                observedItems: [saved, unmanaged, hiddenControl],
                itemSectionMap: [saved.uniqueIdentifier: MenuBarSection.Name.visible.rawValue],
                itemOrder: [
                    MenuBarSection.Name.visible.rawValue: [saved.uniqueIdentifier],
                ]
            )
        )

        let plan = MenuBarSavedLayoutPreparation.prepare(
            observationSnapshot: snapshot,
            savedSectionOrder: [
                MenuBarSection.Name.visible.rawValue: [saved.uniqueIdentifier],
            ],
            newItemsPlacement: newItemsPlacement(section: MenuBarSection.Name.hidden.rawValue),
            settings: MenuBarSavedLayoutPreparation.Settings(
                enableMenuBarItemOverflow: false,
                useLCSOnNotchedDisplay: false
            ),
            screen: nil,
            notchGap: MenuBarSection.notchGap
        )

        XCTAssertEqual(plan.unmanagedPlan.unmanagedUIDs, [unmanaged.uniqueIdentifier])
        XCTAssertEqual(plan.sectionMap[unmanaged.uniqueIdentifier], MenuBarSection.Name.hidden.rawValue)
        XCTAssertEqual(
            plan.desiredFiltered,
            [
                saved.uniqueIdentifier,
                hiddenControl.uniqueIdentifier,
                unmanaged.uniqueIdentifier,
            ]
        )
        XCTAssertEqual(plan.executionPlan, .lcs)
    }

    func testSavedLayoutPreparationAppliesNotchOverflowAndFullSortStrategy() throws {
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 9_021,
            bounds: CGRect(x: 400, y: 0, width: 10, height: 22),
            sourcePID: nil
        )
        let left = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.left", title: "Left"),
            windowID: 9_022,
            bounds: CGRect(x: 520, y: 0, width: 160, height: 22)
        )
        let right = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.right", title: "Right"),
            windowID: 9_023,
            bounds: CGRect(x: 700, y: 0, width: 160, height: 22)
        )
        let controlCenter = MenuBarItem.fixture(
            tag: .controlCenter,
            windowID: 9_024,
            bounds: CGRect(x: 950, y: 0, width: 24, height: 22),
            sourcePID: nil
        )
        let snapshot = try XCTUnwrap(
            savedLayoutPreparationSnapshot(
                observedItems: [left, right, controlCenter, hiddenControl],
                itemSectionMap: [
                    left.uniqueIdentifier: MenuBarSection.Name.visible.rawValue,
                    right.uniqueIdentifier: MenuBarSection.Name.visible.rawValue,
                ],
                itemOrder: [
                    MenuBarSection.Name.visible.rawValue: [
                        left.uniqueIdentifier,
                        right.uniqueIdentifier,
                    ],
                ]
            )
        )

        let plan = MenuBarSavedLayoutPreparation.prepare(
            observationSnapshot: snapshot,
            savedSectionOrder: [
                MenuBarSection.Name.visible.rawValue: [
                    left.uniqueIdentifier,
                    right.uniqueIdentifier,
                ],
            ],
            newItemsPlacement: newItemsPlacement(section: MenuBarSection.Name.hidden.rawValue),
            settings: MenuBarSavedLayoutPreparation.Settings(
                enableMenuBarItemOverflow: true,
                useLCSOnNotchedDisplay: false
            ),
            screen: MenuBarSavedLayoutPreparation.ScreenObservation(
                frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                hasNotch: true,
                notchFrame: CGRect(x: 600, y: 760, width: 120, height: 40)
            ),
            notchGap: 12
        )

        XCTAssertEqual(plan.notchOverflow?.result.overflowUIDs, [left.uniqueIdentifier])
        XCTAssertEqual(plan.sectionMap[left.uniqueIdentifier], MenuBarSection.Name.hidden.rawValue)
        XCTAssertEqual(plan.sectionMap[right.uniqueIdentifier], MenuBarSection.Name.visible.rawValue)
        if case .fullSort = plan.executionPlan {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected full-sort execution on a notched display")
        }
    }

    func testSavedLayoutSectionTransitionPolicyAssessesCrossSectionDrift() {
        let toAlwaysHidden = "com.example.to-ah:To AH"
        let toHidden = "com.example.to-hidden:To Hidden"
        let visible = "com.example.visible:Visible"
        let hiddenControl = "continuum:HiddenControlItem"
        let itemOrder = [
            "visible": [visible],
            "hidden": [toHidden],
            "alwaysHidden": [toAlwaysHidden],
        ]
        let sectionByWindowID: [CGWindowID: MenuBarSection.Name] = [
            230: .hidden,
            231: .alwaysHidden,
            232: .visible,
            233: .hidden,
        ]

        let sets = MenuBarSectionTransitionPolicy.sectionSets(
            observations: [
                sectionTransitionItem(toAlwaysHidden, windowID: 230),
                sectionTransitionItem(toHidden, windowID: 231),
                sectionTransitionItem(visible, windowID: 232),
                sectionTransitionItem(hiddenControl, windowID: 233, isLayoutItem: false),
            ],
            sectionByWindowID: sectionByWindowID,
            itemOrder: itemOrder
        )
        let assessment = MenuBarSectionTransitionPolicy.assess(sets)

        XCTAssertEqual(sets.currentHidden, [toAlwaysHidden])
        XCTAssertEqual(sets.currentAlwaysHidden, [toHidden])
        XCTAssertEqual(sets.desiredVisible, [visible])
        XCTAssertEqual(assessment.wrongInHidden, [toAlwaysHidden])
        XCTAssertEqual(assessment.wrongInAlwaysHidden, [toHidden])
        XCTAssertEqual(assessment.crossSectionMoveCount, 2)
        XCTAssertEqual(assessment.totalSectionMismatch, 2)
        XCTAssertTrue(assessment.requiresAlwaysHiddenControlMove)
    }

    func testSavedLayoutSectionTransitionPolicyBuildsControlMovePlan() {
        let sets = MenuBarSectionTransitionPolicy.SectionSets(
            currentHidden: ["vpn"],
            currentAlwaysHidden: [],
            desiredHidden: ["mail"],
            desiredAlwaysHidden: ["vpn"],
            desiredVisible: []
        )
        let assessment = MenuBarSectionTransitionPolicy.assess(sets)

        XCTAssertEqual(
            MenuBarSectionTransitionPolicy.alwaysHiddenControlMovePlan(
                assessment: assessment,
                itemOrder: ["hidden": ["mail"]],
                hiddenControlUID: "hidden-control",
                alwaysHiddenControlUID: "ah-control"
            ),
            MenuBarSectionTransitionPolicy.AlwaysHiddenControlMovePlan(
                controlUID: "ah-control",
                anchorCandidates: ["mail", "hidden-control"]
            )
        )
        XCTAssertNil(
            MenuBarSectionTransitionPolicy.alwaysHiddenControlMovePlan(
                assessment: assessment,
                itemOrder: ["hidden": ["mail"]],
                hiddenControlUID: "hidden-control",
                alwaysHiddenControlUID: nil
            )
        )
    }

    func testSavedLayoutSectionTransitionPolicyChoosesBoundaryAnchorCandidates() {
        XCTAssertEqual(
            MenuBarSectionTransitionPolicy.alwaysHiddenControlAnchorCandidates(
                itemOrder: ["hidden": ["mail", "clock"]],
                hiddenControlUID: "hidden-control"
            ),
            ["mail", "hidden-control"]
        )
        XCTAssertEqual(
            MenuBarSectionTransitionPolicy.alwaysHiddenControlAnchorCandidates(
                itemOrder: ["alwaysHidden": ["vpn"]],
                hiddenControlUID: "hidden-control"
            ),
            ["hidden-control"]
        )
    }

    func testSavedLayoutSectionTransitionPolicyResolvesBoundaryAnchorUID() {
        let plan = MenuBarSectionTransitionPolicy.AlwaysHiddenControlMovePlan(
            controlUID: "ah-control",
            anchorCandidates: ["mail", "hidden-control"]
        )

        XCTAssertEqual(
            MenuBarSectionTransitionPolicy.resolvedAlwaysHiddenControlAnchorUID(
                for: plan,
                anchors: [
                    MenuBarSectionTransitionPolicy.AnchorObservation(
                        uniqueIdentifier: "mail",
                        isMovable: false
                    ),
                    MenuBarSectionTransitionPolicy.AnchorObservation(
                        uniqueIdentifier: "hidden-control",
                        isMovable: false
                    ),
                ],
                hiddenControlUID: "hidden-control"
            ),
            "hidden-control"
        )
        XCTAssertEqual(
            MenuBarSectionTransitionPolicy.resolvedAlwaysHiddenControlAnchorUID(
                for: plan,
                anchors: [
                    MenuBarSectionTransitionPolicy.AnchorObservation(
                        uniqueIdentifier: "mail",
                        isMovable: true
                    ),
                    MenuBarSectionTransitionPolicy.AnchorObservation(
                        uniqueIdentifier: "hidden-control",
                        isMovable: false
                    ),
                ],
                hiddenControlUID: "hidden-control"
            ),
            "mail"
        )
    }

    func testSavedLayoutSectionTransitionPolicyOrdersFallbackMoves() {
        let plan = MenuBarSectionTransitionPolicy.fallbackPlan(
            currentHidden: ["a1", "a3", "not-desired-ah"],
            currentAlwaysHidden: ["h1", "h3", "not-desired-hidden"],
            itemOrder: [
                "hidden": ["h1", "h2", "h3"],
                "alwaysHidden": ["a1", "a2", "a3"],
            ]
        )

        XCTAssertEqual(plan.toAlwaysHidden, ["a1", "a3"])
        XCTAssertEqual(plan.toHidden, ["h1", "h3"])
        XCTAssertEqual(plan.orderedToAlwaysHidden, ["a3", "a1"])
        XCTAssertEqual(plan.orderedToHidden, ["h1", "h3"])
        XCTAssertEqual(plan.moves, [
            MenuBarSectionTransitionPolicy.FallbackMove(
                uniqueIdentifier: "a3",
                destination: .leftOfAlwaysHiddenControl
            ),
            MenuBarSectionTransitionPolicy.FallbackMove(
                uniqueIdentifier: "a1",
                destination: .leftOfAlwaysHiddenControl
            ),
            MenuBarSectionTransitionPolicy.FallbackMove(
                uniqueIdentifier: "h1",
                destination: .rightOfAlwaysHiddenControl
            ),
            MenuBarSectionTransitionPolicy.FallbackMove(
                uniqueIdentifier: "h3",
                destination: .rightOfAlwaysHiddenControl
            ),
        ])
        XCTAssertTrue(plan.hasMoves)
    }

    func testRuntimeRefreshPolicyKeepsInitialWarmupBounded() {
        XCTAssertEqual(MenuBarRuntimeRefreshPolicy.initialCacheMaxAttempts, 10)
        XCTAssertEqual(MenuBarRuntimeRefreshPolicy.initialCacheAttempts, 1 ... 10)
        XCTAssertEqual(MenuBarRuntimeRefreshPolicy.initialCacheRetryDelay, .milliseconds(100))
        XCTAssertTrue(MenuBarRuntimeRefreshPolicy.shouldRetryInitialCache(after: 9))
        XCTAssertFalse(MenuBarRuntimeRefreshPolicy.shouldRetryInitialCache(after: 10))
    }

    func testRuntimeRefreshPolicyPinsLightweightEventCadence() {
        XCTAssertEqual(MenuBarRuntimeRefreshPolicy.appLaunchDebounce, .seconds(1))
        XCTAssertEqual(MenuBarRuntimeRefreshPolicy.appTerminationDebounce, .seconds(1))
        XCTAssertEqual(MenuBarRuntimeRefreshPolicy.appActivationDebounce, .milliseconds(500))
        XCTAssertEqual(MenuBarRuntimeRefreshPolicy.cacheTickIntervalSeconds, 3)
        XCTAssertEqual(
            MenuBarRuntimeRefreshPolicy.trackedAppLaunchSettlingDuration,
            .seconds(8)
        )
        XCTAssertEqual(
            MenuBarRuntimeRefreshPolicy.appLaunchFollowUpDelays,
            [.milliseconds(2_500), .milliseconds(2_500)]
        )
    }

    @MainActor
    func testInitialCacheExecutorSchedulesAuthoritativeRefreshAfterFastSuccess() async {
        var events = [String]()

        let outcome = await MenuBarInitialCacheExecutor.execute(
            operations: MenuBarInitialCacheExecutor.Operations(
                runFastCache: {
                    events.append("fast")
                    return true
                },
                scheduleAuthoritativeRefresh: {
                    events.append("authoritative")
                },
                sleepBeforeRetry: {
                    events.append("sleep")
                }
            ),
            diagnostics: MenuBarInitialCacheExecutor.Diagnostics(
                recordStart: { events.append("start") },
                recordRetryNeeded: { events.append("retry:\($0)") },
                recordRetrySuccess: { events.append("success:\($0)") }
            )
        )

        XCTAssertEqual(outcome, .completed(attempts: 1, succeeded: true))
        XCTAssertEqual(events, ["start", "fast", "authoritative"])
    }

    @MainActor
    func testInitialCacheExecutorRetriesUntilFastCacheSucceeds() async {
        var attempts = 0
        var events = [String]()

        let outcome = await MenuBarInitialCacheExecutor.execute(
            operations: MenuBarInitialCacheExecutor.Operations(
                runFastCache: {
                    attempts += 1
                    events.append("fast:\(attempts)")
                    return attempts == 3
                },
                scheduleAuthoritativeRefresh: {
                    events.append("authoritative")
                },
                sleepBeforeRetry: {
                    events.append("sleep")
                }
            ),
            diagnostics: MenuBarInitialCacheExecutor.Diagnostics(
                recordRetryNeeded: { events.append("retry:\($0)") },
                recordRetrySuccess: { events.append("success:\($0)") }
            ),
            attempts: 1 ... 3
        )

        XCTAssertEqual(outcome, .completed(attempts: 3, succeeded: true))
        XCTAssertEqual(
            events,
            [
                "fast:1",
                "retry:1",
                "sleep",
                "fast:2",
                "retry:2",
                "sleep",
                "fast:3",
                "success:3",
                "authoritative",
            ]
        )
    }

    @MainActor
    func testInitialCacheExecutorStopsAfterRetryBudgetWithoutAuthoritativeRefresh() async {
        var events = [String]()

        let outcome = await MenuBarInitialCacheExecutor.execute(
            operations: MenuBarInitialCacheExecutor.Operations(
                runFastCache: {
                    events.append("fast")
                    return false
                },
                scheduleAuthoritativeRefresh: {
                    events.append("authoritative")
                },
                sleepBeforeRetry: {
                    events.append("sleep")
                }
            ),
            attempts: 1 ... 2
        )

        XCTAssertEqual(outcome, .completed(attempts: 2, succeeded: false))
        XCTAssertEqual(events, ["fast", "sleep", "fast"])
    }

    @MainActor
    func testInitialCacheExecutorCancellationDuringRetryStopsWarmup() async {
        var events = [String]()

        let outcome = await MenuBarInitialCacheExecutor.execute(
            operations: MenuBarInitialCacheExecutor.Operations(
                runFastCache: {
                    events.append("fast")
                    return false
                },
                scheduleAuthoritativeRefresh: {
                    events.append("authoritative")
                },
                sleepBeforeRetry: {
                    events.append("sleep")
                    throw CancellationError()
                }
            ),
            attempts: 1 ... 3
        )

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(events, ["fast", "sleep"])
    }

    func testStartupSettlingPolicyStartsColdForPerformSetup() {
        let now = ContinuousClock.now

        let decision = MenuBarStartupSettlingPolicy.planStart(
            reason: MenuBarStartupSettlingPolicy.performSetupReason,
            existingKind: nil,
            existingExpectedBundleIDs: [],
            existingDeadline: nil,
            incomingExpectedBundleIDs: [],
            now: now,
            maxDuration: .seconds(30)
        )

        XCTAssertEqual(
            decision,
            .start(
                MenuBarStartupSettlingPolicy.StartConfiguration(
                    kind: .cold,
                    expectedBundleIDs: [],
                    deadline: now.advanced(by: .seconds(30))
                )
            )
        )
    }

    func testStartupSettlingPolicyIgnoresTransientWhenAuthoritativeSettlingIsInFlight() {
        let decision = MenuBarStartupSettlingPolicy.planStart(
            reason: "displayTransition",
            existingKind: .cold,
            existingExpectedBundleIDs: ["com.example.mail"],
            existingDeadline: nil,
            incomingExpectedBundleIDs: [],
            maxDuration: .seconds(8)
        )

        XCTAssertEqual(
            decision,
            .ignore(mergedExpectedBundleIDs: ["com.example.mail"])
        )
    }

    func testStartupSettlingPolicyPromotesExpectedBundleSetAndPreservesLaterDeadline() {
        let now = ContinuousClock.now
        let existingDeadline = now.advanced(by: .seconds(60))

        let decision = MenuBarStartupSettlingPolicy.planStart(
            reason: "appLaunch",
            existingKind: .transient,
            existingExpectedBundleIDs: [],
            existingDeadline: existingDeadline,
            incomingExpectedBundleIDs: ["com.example.mail"],
            now: now,
            maxDuration: .seconds(8)
        )

        XCTAssertEqual(
            decision,
            .start(
                MenuBarStartupSettlingPolicy.StartConfiguration(
                    kind: .expectedSet,
                    expectedBundleIDs: ["com.example.mail"],
                    deadline: existingDeadline
                )
            )
        )
    }

    func testStartupSettlingRuntimeStartsAndFinishesSettlingWindow() {
        let now = ContinuousClock.now
        var runtime = MenuBarStartupSettlingRuntime()

        let decision = runtime.planStart(
            reason: MenuBarStartupSettlingPolicy.performSetupReason,
            incomingExpectedBundleIDs: [],
            now: now,
            maxDuration: .seconds(30)
        )

        XCTAssertEqual(
            decision,
            .start(
                MenuBarStartupSettlingPolicy.StartConfiguration(
                    kind: .cold,
                    expectedBundleIDs: [],
                    deadline: now.advanced(by: .seconds(30))
                )
            )
        )
        XCTAssertTrue(runtime.isActive)

        let task = Task<Void, Never> {}
        runtime.attachSettlingTask(task)
        XCTAssertNotNil(runtime.currentSettlingTask)

        runtime.finishSettling()

        XCTAssertFalse(runtime.isActive)
        XCTAssertNil(runtime.currentSettlingTask)
    }

    func testStartupSettlingRuntimeIgnoresTransientWhenAuthoritativeWindowIsActive() {
        let now = ContinuousClock.now
        var runtime = MenuBarStartupSettlingRuntime()

        _ = runtime.planStart(
            reason: "appLaunch",
            incomingExpectedBundleIDs: ["com.example.mail"],
            now: now,
            maxDuration: .seconds(8)
        )

        let decision = runtime.planStart(
            reason: "displayTransition",
            incomingExpectedBundleIDs: [],
            now: now,
            maxDuration: .seconds(8)
        )

        XCTAssertEqual(decision, .ignore(kindDescription: "expectedSet"))
        XCTAssertTrue(runtime.isActive)
    }

    func testStartupSettlingRuntimeCancelsPreviousSettlingTaskBeforeRestart() async {
        let now = ContinuousClock.now
        var runtime = MenuBarStartupSettlingRuntime()
        let oldTask = Task<Void, Never> {
            while !Task.isCancelled {
                await Task.yield()
            }
        }

        _ = runtime.planStart(
            reason: "displayTransition",
            incomingExpectedBundleIDs: [],
            now: now,
            maxDuration: .seconds(8)
        )
        runtime.attachSettlingTask(oldTask)

        let decision = runtime.planStart(
            reason: MenuBarStartupSettlingPolicy.performSetupReason,
            incomingExpectedBundleIDs: [],
            now: now,
            maxDuration: .seconds(60)
        )

        XCTAssertEqual(
            decision,
            .start(
                MenuBarStartupSettlingPolicy.StartConfiguration(
                    kind: .cold,
                    expectedBundleIDs: [],
                    deadline: now.advanced(by: .seconds(60))
                )
            )
        )
        XCTAssertTrue(oldTask.isCancelled)
        XCTAssertTrue(runtime.isActive)
        XCTAssertNil(runtime.currentSettlingTask)

        _ = await oldTask.value
    }

    func testStartupSettlingRuntimeTracksAndCancelsInitialCacheTask() async {
        var runtime = MenuBarStartupSettlingRuntime()
        let task = Task<Void, Never> {
            while !Task.isCancelled {
                await Task.yield()
            }
        }

        runtime.attachInitialCacheTask(task)
        XCTAssertNotNil(runtime.currentInitialCacheTask)

        runtime.cancelInitialCacheTask()

        XCTAssertNil(runtime.currentInitialCacheTask)
        _ = await task.value
    }

    func testStartupSettlingRuntimeCancelAllClearsBothTaskFamilies() async {
        let now = ContinuousClock.now
        var runtime = MenuBarStartupSettlingRuntime()
        let initialTask = Task<Void, Never> {
            while !Task.isCancelled {
                await Task.yield()
            }
        }
        let settlingTask = Task<Void, Never> {
            while !Task.isCancelled {
                await Task.yield()
            }
        }

        runtime.attachInitialCacheTask(initialTask)
        _ = runtime.planStart(
            reason: MenuBarStartupSettlingPolicy.performSetupReason,
            incomingExpectedBundleIDs: [],
            now: now,
            maxDuration: .seconds(60)
        )
        runtime.attachSettlingTask(settlingTask)

        runtime.cancelAll()

        XCTAssertFalse(runtime.isActive)
        XCTAssertNil(runtime.currentInitialCacheTask)
        XCTAssertNil(runtime.currentSettlingTask)
        XCTAssertTrue(initialTask.isCancelled)
        XCTAssertTrue(settlingTask.isCancelled)

        _ = await initialTask.value
        _ = await settlingTask.value
    }

    @MainActor
    func testStartupSettlingExecutorRunsFinalRestoreForExpectedSet() async {
        let now = ContinuousClock.now
        let configuration = MenuBarStartupSettlingPolicy.StartConfiguration(
            kind: .expectedSet,
            expectedBundleIDs: ["com.example.mail"],
            deadline: now.advanced(by: .seconds(30))
        )
        var events = [String]()

        let outcome = await MenuBarStartupSettlingExecutor.execute(
            configuration: configuration,
            operations: MenuBarStartupSettlingExecutor.Operations(
                waitForInitialCache: { events.append("initial") },
                pollCache: {
                    events.append("poll")
                    return MenuBarStartupSettlingExecutor.Observation(
                        managedItemCount: 1,
                        unresolvedSourcePIDCount: 0,
                        presentBundleIDs: ["com.example.mail"]
                    )
                },
                finishSettlingWindow: { events.append("finish") },
                runFastRestore: { events.append("fast") },
                runAuthoritativeRestore: { events.append("authoritative") },
                sleepBetweenPolls: { events.append("sleep") },
                now: { now }
            ),
            diagnostics: MenuBarStartupSettlingExecutor.Diagnostics(
                recordWaitingForExpectedSet: { events.append("waiting:\($0.count)") },
                recordSettled: { _ in events.append("settled") },
                recordEnded: { events.append("ended") },
                recordFastRestoreStart: { events.append("fastStart") }
            )
        )

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(
            events,
            ["initial", "waiting:1", "poll", "settled", "finish", "ended", "fastStart", "fast", "authoritative"]
        )
    }

    @MainActor
    func testStartupSettlingExecutorPollsUntilColdStartCountIsStable() async {
        let now = ContinuousClock.now
        let configuration = MenuBarStartupSettlingPolicy.StartConfiguration(
            kind: .cold,
            expectedBundleIDs: [],
            deadline: now.advanced(by: .seconds(30))
        )
        var pollCount = 0
        var sleepCount = 0
        var didFinish = false

        let outcome = await MenuBarStartupSettlingExecutor.execute(
            configuration: configuration,
            operations: MenuBarStartupSettlingExecutor.Operations(
                waitForInitialCache: {},
                pollCache: {
                    pollCount += 1
                    return MenuBarStartupSettlingExecutor.Observation(
                        managedItemCount: 2,
                        unresolvedSourcePIDCount: 0,
                        presentBundleIDs: ["com.example.mail", "com.example.chat"]
                    )
                },
                finishSettlingWindow: { didFinish = true },
                runFastRestore: {},
                runAuthoritativeRestore: {},
                sleepBetweenPolls: { sleepCount += 1 },
                now: { now }
            )
        )

        XCTAssertEqual(outcome, .completed)
        XCTAssertTrue(didFinish)
        XCTAssertEqual(pollCount, 4)
        XCTAssertEqual(sleepCount, 3)
    }

    @MainActor
    func testStartupSettlingExecutorDeadlineFallsBackToFinalRestore() async {
        let now = ContinuousClock.now
        let configuration = MenuBarStartupSettlingPolicy.StartConfiguration(
            kind: .transient,
            expectedBundleIDs: [],
            deadline: now
        )
        var events = [String]()

        let outcome = await MenuBarStartupSettlingExecutor.execute(
            configuration: configuration,
            operations: MenuBarStartupSettlingExecutor.Operations(
                waitForInitialCache: { events.append("initial") },
                pollCache: {
                    events.append("poll")
                    return MenuBarStartupSettlingExecutor.Observation(
                        managedItemCount: 0,
                        unresolvedSourcePIDCount: 0,
                        presentBundleIDs: []
                    )
                },
                finishSettlingWindow: { events.append("finish") },
                runFastRestore: { events.append("fast") },
                runAuthoritativeRestore: { events.append("authoritative") },
                sleepBetweenPolls: { events.append("sleep") },
                now: { now.advanced(by: .seconds(1)) }
            ),
            diagnostics: MenuBarStartupSettlingExecutor.Diagnostics(
                recordDeadlineReached: { _ in events.append("deadline") }
            )
        )

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(events, ["initial", "deadline", "finish", "fast", "authoritative"])
    }

    @MainActor
    func testStartupSettlingExecutorCancellationDuringSleepSkipsFinalRestore() async {
        let now = ContinuousClock.now
        let configuration = MenuBarStartupSettlingPolicy.StartConfiguration(
            kind: .cold,
            expectedBundleIDs: [],
            deadline: now.advanced(by: .seconds(30))
        )
        var events = [String]()

        let outcome = await MenuBarStartupSettlingExecutor.execute(
            configuration: configuration,
            operations: MenuBarStartupSettlingExecutor.Operations(
                waitForInitialCache: { events.append("initial") },
                pollCache: {
                    events.append("poll")
                    return MenuBarStartupSettlingExecutor.Observation(
                        managedItemCount: 0,
                        unresolvedSourcePIDCount: 0,
                        presentBundleIDs: []
                    )
                },
                finishSettlingWindow: { events.append("finish") },
                runFastRestore: { events.append("fast") },
                runAuthoritativeRestore: { events.append("authoritative") },
                sleepBetweenPolls: {
                    events.append("sleep")
                    throw CancellationError()
                },
                now: { now }
            ),
            diagnostics: MenuBarStartupSettlingExecutor.Diagnostics(
                recordCancelled: { events.append("cancelled") }
            )
        )

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(events, ["initial", "poll", "sleep", "cancelled"])
    }

    func testStartupSettlingPollWaitsForExpectedBundleIDsThenSettlesWhenSourcePIDsResolved() {
        let state = MenuBarStartupSettlingPolicy.PollState.initial
        let waitingFor: Set<String> = ["com.example.mail", "com.example.chat"]

        XCTAssertEqual(
            MenuBarStartupSettlingPolicy.evaluatePoll(
                observation: MenuBarStartupSettlingPolicy.PollObservation(
                    managedItemCount: 2,
                    unresolvedSourcePIDCount: 0,
                    presentBundleIDs: ["com.example.mail"]
                ),
                waitingFor: waitingFor,
                state: state
            ),
            .wait(
                nextState: state,
                reason: .missingExpectedBundleIDs(["com.example.chat"])
            )
        )
        XCTAssertEqual(
            MenuBarStartupSettlingPolicy.evaluatePoll(
                observation: MenuBarStartupSettlingPolicy.PollObservation(
                    managedItemCount: 2,
                    unresolvedSourcePIDCount: 2,
                    presentBundleIDs: waitingFor
                ),
                waitingFor: waitingFor,
                state: state
            ),
            .wait(
                nextState: state,
                reason: .sourcePIDsUnresolved(
                    managedItemCount: 2,
                    unresolvedSourcePIDCount: 2
                )
            )
        )
        XCTAssertEqual(
            MenuBarStartupSettlingPolicy.evaluatePoll(
                observation: MenuBarStartupSettlingPolicy.PollObservation(
                    managedItemCount: 2,
                    unresolvedSourcePIDCount: 1,
                    presentBundleIDs: waitingFor
                ),
                waitingFor: waitingFor,
                state: state
            ),
            .settled(.expectedBundleIDsReattached(count: 2))
        )
    }

    func testStartupSettlingPollRequiresStableCountAndResolvedSourcePIDs() {
        let first = MenuBarStartupSettlingPolicy.evaluatePoll(
            observation: MenuBarStartupSettlingPolicy.PollObservation(
                managedItemCount: 4,
                unresolvedSourcePIDCount: 0,
                presentBundleIDs: []
            ),
            waitingFor: [],
            state: .initial
        )
        XCTAssertEqual(
            first,
            .wait(
                nextState: MenuBarStartupSettlingPolicy.PollState(
                    lastSeenCount: 4,
                    stablePolls: 0
                ),
                reason: .countChanged(previous: -1, current: 4, unresolvedSourcePIDCount: 0)
            )
        )

        let secondState = MenuBarStartupSettlingPolicy.PollState(
            lastSeenCount: 4,
            stablePolls: 0
        )
        let second = MenuBarStartupSettlingPolicy.evaluatePoll(
            observation: MenuBarStartupSettlingPolicy.PollObservation(
                managedItemCount: 4,
                unresolvedSourcePIDCount: 0,
                presentBundleIDs: []
            ),
            waitingFor: [],
            state: secondState
        )
        XCTAssertEqual(
            second,
            .wait(
                nextState: MenuBarStartupSettlingPolicy.PollState(
                    lastSeenCount: 4,
                    stablePolls: 1
                ),
                reason: .waitingForStableCount(
                    count: 4,
                    stablePolls: 1,
                    target: 3,
                    unresolvedSourcePIDCount: 0
                )
            )
        )

        let final = MenuBarStartupSettlingPolicy.evaluatePoll(
            observation: MenuBarStartupSettlingPolicy.PollObservation(
                managedItemCount: 4,
                unresolvedSourcePIDCount: 0,
                presentBundleIDs: []
            ),
            waitingFor: [],
            state: MenuBarStartupSettlingPolicy.PollState(
                lastSeenCount: 4,
                stablePolls: 2
            )
        )
        XCTAssertEqual(
            final,
            .settled(
                .countStable(
                    count: 4,
                    stablePolls: 3,
                    unresolvedSourcePIDCount: 0
                )
            )
        )
    }

    func testMoveCommandVerifiesPlacementAgainstExpectedSection() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 89,
            sourcePID: 1234
        )
        let target = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 90,
            sourcePID: 1235
        )
        var cache = MenuBarItemCache(displayID: 126)
        cache[.hidden] = [item, target]
        let command = MenuBarMoveCommand(
            item: item,
            destination: .leftOfItem(target),
            displayID: nil,
            skipInputPause: false,
            watchdogTimeout: nil,
            maxMoveAttempts: 8
        )

        XCTAssertEqual(
            command.placementVerification(expectedSection: .hidden, cache: cache),
            .reachedDestination
        )
        XCTAssertTrue(command.didReachDestination(expectedSection: .hidden, cache: cache))
        XCTAssertEqual(
            command.placementVerification(expectedSection: .visible, cache: cache),
            .itemMissingFromExpectedSection
        )
    }

    func testMoveVerificationRequiresAdjacencyForNonControlTargets() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 91,
            sourcePID: 1234
        )
        let target = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.anchor", title: "Anchor"),
            windowID: 92,
            sourcePID: 1235
        )
        let other = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.other", title: "Other"),
            windowID: 93,
            sourcePID: 1236
        )
        var cache = MenuBarItemCache(displayID: 126)
        cache[.hidden] = [item, other, target]

        XCTAssertEqual(
            MenuBarMoveVerification.evaluate(
                item: item,
                destination: .leftOfItem(target),
                expectedSection: .hidden,
                cache: cache
            ),
            .wrongRelativePosition(itemIndex: 0, targetIndex: 2, relation: .leftOfItem)
        )
    }

    func testMoveVerificationAcceptsControlTargetAsSectionContainment() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 94,
            sourcePID: 1234
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 95,
            sourcePID: nil
        )
        var cache = MenuBarItemCache(displayID: 126)
        cache[.visible] = [item]

        XCTAssertEqual(
            MenuBarMoveVerification.evaluate(
                item: item,
                destination: .rightOfItem(hiddenControl),
                expectedSection: .visible,
                cache: cache
            ),
            .reachedDestination
        )
    }

    func testCacheInvalidationKeepsCacheWhenWindowIDsMatch() {
        let decision = MenuBarCacheInvalidation.evaluate(
            cachedWindowIDs: [1, 2, 3],
            observedWindowIDs: [1, 2, 3],
            cloneWindowIDs: []
        )

        XCTAssertFalse(decision.shouldRecache)
        XCTAssertEqual(decision.normalizedWindowIDs, [1, 2, 3])
        XCTAssertEqual(decision.action, .keepCurrentCache)
    }

    func testCacheInvalidationIgnoresKnownCloneWindows() {
        let decision = MenuBarCacheInvalidation.evaluate(
            cachedWindowIDs: [1, 2, 3],
            observedWindowIDs: [1, 99, 2, 3],
            cloneWindowIDs: [99]
        )

        XCTAssertFalse(decision.shouldRecache)
        XCTAssertEqual(decision.normalizedWindowIDs, [1, 2, 3])
    }

    func testCacheInvalidationRecachesWhenNormalizedWindowIDsChange() {
        let addition = MenuBarCacheInvalidation.evaluate(
            cachedWindowIDs: [1, 2, 3],
            observedWindowIDs: [1, 2, 3, 4],
            cloneWindowIDs: []
        )
        let removal = MenuBarCacheInvalidation.evaluate(
            cachedWindowIDs: [1, 2, 3],
            observedWindowIDs: [1, 3],
            cloneWindowIDs: []
        )
        let reorder = MenuBarCacheInvalidation.evaluate(
            cachedWindowIDs: [1, 2, 3],
            observedWindowIDs: [1, 3, 2],
            cloneWindowIDs: []
        )

        XCTAssertTrue(addition.shouldRecache)
        XCTAssertTrue(removal.shouldRecache)
        XCTAssertTrue(reorder.shouldRecache)
        XCTAssertEqual(addition.action, .recache)
    }

    func testCacheLedgerRecordsObservationAndSourcePIDBaselines() {
        var ledger = MenuBarCacheLedger()

        ledger.recordObservation(
            itemWindowIDs: [101, 102],
            cloneWindowIDs: [999]
        )
        ledger.recordResolvedSourcePIDs([101: 2001, 102: 2002])

        XCTAssertEqual(ledger.cachedItemWindowIDs, [101, 102])
        XCTAssertEqual(ledger.cachedCloneWindowIDs, [999])
        XCTAssertEqual(ledger.cachedItemPIDs, [101: 2001, 102: 2002])
    }

    func testCacheLedgerClearResetsAllBaselinesTogether() {
        var ledger = MenuBarCacheLedger()
        ledger.recordObservation(
            itemWindowIDs: [101, 102],
            cloneWindowIDs: [999]
        )
        ledger.recordResolvedSourcePIDs([101: 2001])

        ledger.clear()

        XCTAssertTrue(ledger.cachedItemWindowIDs.isEmpty)
        XCTAssertTrue(ledger.cachedCloneWindowIDs.isEmpty)
        XCTAssertTrue(ledger.cachedItemPIDs.isEmpty)
    }

    func testCacheCycleRuntimeSerializesCacheCycles() async {
        let runtime = MenuBarCacheCycleRuntime()
        let firstAcquire = await runtime.operationGate.begin()
        let blockedAcquire = await runtime.operationGate.begin()

        XCTAssertTrue(firstAcquire)
        XCTAssertFalse(blockedAcquire)

        await runtime.operationGate.end()

        let reacquired = await runtime.operationGate.begin()

        XCTAssertTrue(reacquired)

        await runtime.operationGate.end()
    }

    func testCacheCycleRuntimeOwnsCacheBaselines() {
        var runtime = MenuBarCacheCycleRuntime()

        runtime.recordObservation(
            itemWindowIDs: [201, 202],
            cloneWindowIDs: [999]
        )
        runtime.recordResolvedSourcePIDs([201: 3001])

        XCTAssertEqual(runtime.cachedItemWindowIDs, [201, 202])
        XCTAssertEqual(runtime.cachedCloneWindowIDs, [999])
        XCTAssertEqual(runtime.cachedItemPIDs, [201: 3001])

        runtime.clearLedger()

        XCTAssertTrue(runtime.cachedItemWindowIDs.isEmpty)
        XCTAssertTrue(runtime.cachedCloneWindowIDs.isEmpty)
        XCTAssertTrue(runtime.cachedItemPIDs.isEmpty)
    }

    func testCacheCycleRuntimeDrainsBackgroundContinuationOnce() async {
        var runtime = MenuBarCacheCycleRuntime()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            runtime.storeBackgroundContinuation(continuation)
            XCTAssertTrue(runtime.hasPendingBackgroundContinuation)
            runtime.resumeBackgroundContinuation()
        }

        XCTAssertFalse(runtime.hasPendingBackgroundContinuation)

        runtime.resumeBackgroundContinuation()

        XCTAssertFalse(runtime.hasPendingBackgroundContinuation)
    }

    func testCacheCycleRuntimeMovesBackgroundContinuationToFollowUpRecache() async {
        var runtime = MenuBarCacheCycleRuntime()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            runtime.storeBackgroundContinuation(continuation)
            guard case let .start(token) = runtime.scheduleFollowUpRecache() else {
                XCTFail("Expected follow-up recache to schedule")
                runtime.resumeBackgroundContinuation()
                return
            }

            XCTAssertFalse(runtime.hasPendingBackgroundContinuation)
            XCTAssertTrue(runtime.hasPendingFollowUpContinuation)
            XCTAssertTrue(runtime.beginFollowUpRecache(token))
            XCTAssertEqual(runtime.finishFollowUpRecache(token), .idle)
        }

        XCTAssertFalse(runtime.hasPendingFollowUpContinuation)
        XCTAssertFalse(runtime.hasScheduledFollowUpRecache)
    }

    func testCacheCycleRuntimeReschedulesSleepingFollowUpRecache() {
        var runtime = MenuBarCacheCycleRuntime()

        guard case let .start(firstToken) = runtime.scheduleFollowUpRecache() else {
            XCTFail("Expected first follow-up recache to schedule")
            return
        }
        guard case let .start(secondToken) = runtime.scheduleFollowUpRecache() else {
            XCTFail("Expected sleeping follow-up recache to reschedule")
            return
        }

        XCTAssertNotEqual(firstToken, secondToken)
        XCTAssertFalse(runtime.beginFollowUpRecache(firstToken))
        XCTAssertTrue(runtime.beginFollowUpRecache(secondToken))
        XCTAssertEqual(runtime.finishFollowUpRecache(secondToken), .idle)
        XCTAssertFalse(runtime.hasScheduledFollowUpRecache)
    }

    func testCacheCycleRuntimeSchedulesAnotherFollowUpAfterRunningRecache() {
        var runtime = MenuBarCacheCycleRuntime()

        guard case let .start(firstToken) = runtime.scheduleFollowUpRecache() else {
            XCTFail("Expected first follow-up recache to schedule")
            return
        }
        XCTAssertTrue(runtime.beginFollowUpRecache(firstToken))
        XCTAssertEqual(runtime.scheduleFollowUpRecache(), .waitForRunningFollowUp)

        guard case let .startNext(secondToken) = runtime.finishFollowUpRecache(firstToken) else {
            XCTFail("Expected another follow-up recache after running recache finishes")
            return
        }

        XCTAssertNotEqual(firstToken, secondToken)
        XCTAssertTrue(runtime.beginFollowUpRecache(secondToken))
        XCTAssertEqual(runtime.finishFollowUpRecache(secondToken), .idle)
        XCTAssertFalse(runtime.hasScheduledFollowUpRecache)
    }

    func testCacheCycleRuntimeCancelFollowUpRecacheResumesContinuation() async {
        var runtime = MenuBarCacheCycleRuntime()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            runtime.storeBackgroundContinuation(continuation)
            guard case .start = runtime.scheduleFollowUpRecache() else {
                XCTFail("Expected follow-up recache to schedule")
                runtime.resumeBackgroundContinuation()
                return
            }

            XCTAssertTrue(runtime.hasPendingFollowUpContinuation)
            runtime.cancelFollowUpRecache()
        }

        XCTAssertFalse(runtime.hasPendingFollowUpContinuation)
        XCTAssertFalse(runtime.hasScheduledFollowUpRecache)
    }

    func testDeferredCacheRefreshRuntimeCoalescesPendingRequests() {
        var runtime = MenuBarDeferredCacheRefreshRuntime()

        let firstDecision = runtime.schedule()

        guard case .schedule = firstDecision else {
            XCTFail("Expected first deferred refresh request to schedule")
            return
        }
        XCTAssertTrue(runtime.hasPendingRefresh)
        XCTAssertEqual(runtime.schedule(), .alreadyScheduled)
        XCTAssertTrue(runtime.hasPendingRefresh)
    }

    func testDeferredCacheRefreshRuntimeIgnoresStaleCompletion() {
        var runtime = MenuBarDeferredCacheRefreshRuntime()

        guard case let .schedule(firstToken) = runtime.schedule() else {
            XCTFail("Expected first deferred refresh request to schedule")
            return
        }

        runtime.finish(firstToken)
        guard case let .schedule(secondToken) = runtime.schedule() else {
            XCTFail("Expected second deferred refresh request to schedule after completion")
            return
        }

        runtime.finish(firstToken)

        XCTAssertTrue(runtime.hasPendingRefresh)
        runtime.finish(secondToken)
        XCTAssertFalse(runtime.hasPendingRefresh)
    }

    func testDeferredCacheRefreshRuntimeCancelClearsPendingRequest() {
        var runtime = MenuBarDeferredCacheRefreshRuntime()

        guard case let .schedule(token) = runtime.schedule() else {
            XCTFail("Expected deferred refresh request to schedule")
            return
        }

        runtime.attachTask(Task {}, for: token)
        XCTAssertTrue(runtime.hasPendingRefresh)

        runtime.cancel()

        XCTAssertFalse(runtime.hasPendingRefresh)
        guard case .schedule = runtime.schedule() else {
            XCTFail("Expected scheduling to recover after cancellation")
            return
        }
    }

    func testEventRefreshRuntimeStartsImmediatelyWhenIdle() {
        var runtime = MenuBarEventRefreshRuntime()

        let request = MenuBarEventRefreshRuntime.Request.ifNeeded
        guard case let .start(token, startedRequest) = runtime.schedule(request) else {
            XCTFail("Expected idle event refresh runtime to start")
            return
        }

        XCTAssertEqual(startedRequest, request)
        XCTAssertTrue(runtime.hasActiveRefresh)
        XCTAssertFalse(runtime.hasPendingRefresh)
        XCTAssertEqual(runtime.finish(token), .idle)
        XCTAssertFalse(runtime.hasActiveRefresh)
    }

    func testEventRefreshRuntimeCoalescesPendingRequestBehindActiveRefresh() {
        var runtime = MenuBarEventRefreshRuntime()
        let followUpDelays: [Duration] = [.milliseconds(2_500), .milliseconds(2_500)]
        let fullRefresh = MenuBarEventRefreshRuntime.Request.fullRefresh(
            followUpDelays: followUpDelays
        )

        guard case let .start(firstToken, _) = runtime.schedule(.ifNeeded) else {
            XCTFail("Expected first event refresh request to start")
            return
        }

        XCTAssertEqual(runtime.schedule(.ifNeeded), .coalesced(.ifNeeded))
        XCTAssertEqual(runtime.schedule(fullRefresh), .coalesced(fullRefresh))
        XCTAssertTrue(runtime.hasPendingRefresh)

        guard case let .startNext(secondToken, nextRequest) = runtime.finish(firstToken) else {
            XCTFail("Expected pending event refresh request to start after active finish")
            return
        }

        XCTAssertNotEqual(secondToken, firstToken)
        XCTAssertEqual(nextRequest, fullRefresh)
        XCTAssertTrue(runtime.hasActiveRefresh)
        XCTAssertFalse(runtime.hasPendingRefresh)
        XCTAssertEqual(runtime.finish(secondToken), .idle)
        XCTAssertFalse(runtime.hasActiveRefresh)
    }

    func testEventRefreshRuntimeIgnoresStaleFinishAndCancelClearsState() {
        var runtime = MenuBarEventRefreshRuntime()

        guard case let .start(firstToken, _) = runtime.schedule(.ifNeeded) else {
            XCTFail("Expected first event refresh request to start")
            return
        }
        XCTAssertEqual(runtime.schedule(.ifNeeded), .coalesced(.ifNeeded))
        guard case let .startNext(secondToken, _) = runtime.finish(firstToken) else {
            XCTFail("Expected pending event refresh request to start")
            return
        }

        XCTAssertNotEqual(secondToken, firstToken)
        XCTAssertEqual(runtime.finish(firstToken), .idle)
        XCTAssertTrue(runtime.hasActiveRefresh)

        runtime.attachTask(Task {}, for: secondToken)
        runtime.cancel()

        XCTAssertFalse(runtime.hasActiveRefresh)
        XCTAssertFalse(runtime.hasPendingRefresh)
    }

    func testLayoutMutationStateTracksResetScope() {
        var state = MenuBarLayoutMutationState()

        state.beginReset()
        XCTAssertTrue(state.isResettingLayout)
        XCTAssertFalse(state.isRestoringItemOrder)

        state.endReset()
        XCTAssertFalse(state.isResettingLayout)
    }

    func testLayoutMutationStateTracksSavedLayoutRestoreScope() {
        var state = MenuBarLayoutMutationState()
        let startedAt = Date(timeIntervalSince1970: 100)

        state.beginSavedLayoutRestore(now: startedAt)
        XCTAssertTrue(state.isRestoringItemOrder)
        XCTAssertEqual(state.restoringItemOrderStartedAt, startedAt)

        state.endSavedLayoutRestore()
        XCTAssertFalse(state.isRestoringItemOrder)
        XCTAssertNil(state.restoringItemOrderStartedAt)
    }

    func testLayoutMutationStateClearsOnlyStaleSavedLayoutRestore() {
        var state = MenuBarLayoutMutationState()
        let startedAt = Date(timeIntervalSince1970: 100)
        state.beginSavedLayoutRestore(now: startedAt)

        XCTAssertFalse(
            state.clearStaleSavedLayoutRestoreIfNeeded(
                now: Date(timeIntervalSince1970: 109)
            )
        )
        XCTAssertTrue(state.isRestoringItemOrder)

        XCTAssertTrue(
            state.clearStaleSavedLayoutRestoreIfNeeded(
                now: Date(timeIntervalSince1970: 111)
            )
        )
        XCTAssertFalse(state.isRestoringItemOrder)
        XCTAssertNil(state.restoringItemOrderStartedAt)
    }

    func testLayoutResetPolicyAllowsOnlyResettableItems() {
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 301
        )
        let visibleControl = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 302,
            sourcePID: nil
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 303,
            sourcePID: nil
        )

        XCTAssertTrue(MenuBarLayoutResetPolicy.canMoveToHiddenDuringReset(appItem))
        XCTAssertFalse(MenuBarLayoutResetPolicy.canMoveToHiddenDuringReset(visibleControl))
        XCTAssertFalse(MenuBarLayoutResetPolicy.canMoveToHiddenDuringReset(hiddenControl))
    }

    func testLayoutResetPolicyBuildsMoveCandidates() {
        let appItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 304
        )
        let visibleControl = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 305,
            sourcePID: nil
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 306,
            sourcePID: nil
        )

        XCTAssertEqual(
            MenuBarLayoutResetPolicy.moveCandidates(
                from: [visibleControl, appItem, hiddenControl]
            ).map(\.windowID),
            [appItem.windowID]
        )
    }

    func testLayoutResetPolicyPlansControlRecoveryAndPacing() {
        XCTAssertEqual(
            MenuBarLayoutResetPolicy.controlRecoveryAction(alwaysHiddenSectionEnabled: true),
            .toggleAlwaysHiddenSection
        )
        XCTAssertEqual(
            MenuBarLayoutResetPolicy.controlRecoveryAction(alwaysHiddenSectionEnabled: false),
            .fail
        )
        XCTAssertEqual(
            MenuBarLayoutResetPolicy.delay(after: .controlRecoveryDisableSettle),
            .milliseconds(50)
        )
        XCTAssertEqual(
            MenuBarLayoutResetPolicy.delay(after: .controlRecoveryEnableSettle),
            .milliseconds(150)
        )
        XCTAssertEqual(
            MenuBarLayoutResetPolicy.delay(after: .firstPassSettle),
            .milliseconds(200)
        )
        XCTAssertEqual(
            MenuBarLayoutResetPolicy.delay(after: .cacheFallbackSettle),
            .milliseconds(350)
        )
    }

    func testLayoutResetPolicyRetriesItemsStillOutsideHiddenSection() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 307
        )
        let hiddenControlBounds = CGRect(x: 100, y: 0, width: 10, height: 22)
        let alwaysHiddenControlBounds = CGRect(x: 40, y: 0, width: 10, height: 22)

        XCTAssertTrue(
            MenuBarLayoutResetPolicy.shouldRetryMoveToHidden(
                item: item,
                itemBounds: CGRect(x: 120, y: 0, width: 20, height: 22),
                hiddenControlBounds: hiddenControlBounds,
                alwaysHiddenControlBounds: alwaysHiddenControlBounds
            )
        )
        XCTAssertTrue(
            MenuBarLayoutResetPolicy.shouldRetryMoveToHidden(
                item: item,
                itemBounds: CGRect(x: 10, y: 0, width: 20, height: 22),
                hiddenControlBounds: hiddenControlBounds,
                alwaysHiddenControlBounds: alwaysHiddenControlBounds
            )
        )
        XCTAssertFalse(
            MenuBarLayoutResetPolicy.shouldRetryMoveToHidden(
                item: item,
                itemBounds: CGRect(x: 60, y: 0, width: 20, height: 22),
                hiddenControlBounds: hiddenControlBounds,
                alwaysHiddenControlBounds: alwaysHiddenControlBounds
            )
        )
    }

    func testLayoutResetPolicyBuildsSecondPassCandidates() {
        let visibleItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.visible", title: "Visible"),
            windowID: 308
        )
        let hiddenItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.hidden", title: "Hidden"),
            windowID: 309
        )
        let alwaysHiddenItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.always", title: "Always"),
            windowID: 310
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 311,
            sourcePID: nil
        )
        let boundsByWindowID: [CGWindowID: CGRect] = [
            visibleItem.windowID: CGRect(x: 120, y: 0, width: 20, height: 22),
            hiddenItem.windowID: CGRect(x: 60, y: 0, width: 20, height: 22),
            alwaysHiddenItem.windowID: CGRect(x: 10, y: 0, width: 20, height: 22),
            hiddenControl.windowID: CGRect(x: 100, y: 0, width: 10, height: 22),
        ]

        let candidates = MenuBarLayoutResetPolicy.secondPassCandidates(
            items: [visibleItem, hiddenItem, alwaysHiddenItem, hiddenControl],
            hiddenControlBounds: CGRect(x: 100, y: 0, width: 10, height: 22),
            alwaysHiddenControlBounds: CGRect(x: 40, y: 0, width: 10, height: 22)
        ) { item in
            boundsByWindowID[item.windowID] ?? item.bounds
        }

        XCTAssertEqual(candidates.map(\.windowID), [visibleItem.windowID, alwaysHiddenItem.windowID])
    }

    @MainActor
    func testLayoutResetExecutorRunsSecondPassForItemsStillOutsideHiddenSection() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.visible", title: "Visible"),
            windowID: 314,
            bounds: CGRect(x: 140, y: 0, width: 20, height: 22)
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 315,
            bounds: CGRect(x: 100, y: 0, width: 10, height: 22),
            sourcePID: nil
        )
        var observations = [
            [item, hiddenControl],
            [item, hiddenControl],
        ]
        var observedContexts = [String]()
        var moved = [(MenuBarItem, MenuBarMoveDestination)]()
        var sleepDurations = [Duration]()
        var secondPassCounts = [Int]()

        let outcome = await MenuBarLayoutResetExecutor.execute(
            alwaysHiddenSectionEnabled: false,
            controlItemWindowIDs: MenuBarControlItemWindowIDs(hidden: hiddenControl.windowID),
            operations: MenuBarLayoutResetExecutor.Operations(
                observeItems: { context in
                    observedContexts.append(context)
                    return observations.removeFirst()
                },
                setAlwaysHiddenSectionEnabled: { _ in
                    XCTFail("Always-hidden toggle should not run when controls are present")
                },
                enforceControlItemOrder: { _ in },
                moveItem: { item, destination in
                    moved.append((item, destination))
                },
                boundsForItem: { item in item.bounds },
                sleep: { duration in
                    sleepDurations.append(duration)
                }
            ),
            diagnostics: MenuBarLayoutResetExecutor.Diagnostics(
                recordSecondPassStart: { count in
                    secondPassCounts.append(count)
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarLayoutResetExecutor.Outcome(
                firstPassMoveCount: 1,
                firstPassFailureCount: 0,
                secondPassMoveCount: 1,
                failedMoveCount: 0,
                controlRecoveryAttempted: false,
                stopReason: .completed
            )
        )
        XCTAssertEqual(observedContexts, ["layoutResetInitial", "layoutResetSecondPass"])
        XCTAssertEqual(moved.map(\.0.windowID), [item.windowID, item.windowID])
        XCTAssertEqual(moved.map { $0.1.isLeftOfTarget }, [true, true])
        XCTAssertEqual(
            moved.map { $0.1.targetItem.windowID },
            [hiddenControl.windowID, hiddenControl.windowID]
        )
        XCTAssertEqual(sleepDurations, [MenuBarLayoutResetPolicy.delay(after: .firstPassSettle)])
        XCTAssertEqual(secondPassCounts, [1])
    }

    @MainActor
    func testLayoutResetExecutorRecoversMissingControlsByTogglingAlwaysHiddenSection() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.recover", title: "Recover"),
            windowID: 316,
            bounds: CGRect(x: 140, y: 0, width: 20, height: 22)
        )
        let settledItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.recover", title: "Recover"),
            windowID: 316,
            bounds: CGRect(x: 70, y: 0, width: 20, height: 22)
        )
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 317,
            bounds: CGRect(x: 100, y: 0, width: 10, height: 22),
            sourcePID: nil
        )
        var observations = [
            [item],
            [item, hiddenControl],
            [settledItem, hiddenControl],
        ]
        var observedContexts = [String]()
        var toggles = [Bool]()
        var enforcedControlIDs = [CGWindowID]()
        var moved = [MenuBarItem]()
        var sleepDurations = [Duration]()
        var didRecover = false

        let outcome = await MenuBarLayoutResetExecutor.execute(
            alwaysHiddenSectionEnabled: true,
            controlItemWindowIDs: MenuBarControlItemWindowIDs(hidden: hiddenControl.windowID),
            operations: MenuBarLayoutResetExecutor.Operations(
                observeItems: { context in
                    observedContexts.append(context)
                    return observations.removeFirst()
                },
                setAlwaysHiddenSectionEnabled: { isEnabled in
                    toggles.append(isEnabled)
                },
                enforceControlItemOrder: { controlItems in
                    enforcedControlIDs.append(controlItems.hidden.windowID)
                },
                moveItem: { item, _ in
                    moved.append(item)
                },
                boundsForItem: { item in item.bounds },
                sleep: { duration in
                    sleepDurations.append(duration)
                }
            ),
            diagnostics: MenuBarLayoutResetExecutor.Diagnostics(
                recordControlRecoverySuccess: {
                    didRecover = true
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarLayoutResetExecutor.Outcome(
                firstPassMoveCount: 1,
                firstPassFailureCount: 0,
                secondPassMoveCount: 0,
                failedMoveCount: 0,
                controlRecoveryAttempted: true,
                stopReason: .completed
            )
        )
        XCTAssertTrue(didRecover)
        XCTAssertEqual(
            observedContexts,
            ["layoutResetInitial", "layoutResetControlRetry", "layoutResetSecondPass"]
        )
        XCTAssertEqual(toggles, [false, true])
        XCTAssertEqual(enforcedControlIDs, [hiddenControl.windowID])
        XCTAssertEqual(moved.map(\.windowID), [item.windowID])
        XCTAssertEqual(
            sleepDurations,
            [
                MenuBarLayoutResetPolicy.delay(after: .controlRecoveryDisableSettle),
                MenuBarLayoutResetPolicy.delay(after: .controlRecoveryEnableSettle),
                MenuBarLayoutResetPolicy.delay(after: .firstPassSettle),
            ]
        )
    }

    @MainActor
    func testLayoutResetExecutorReportsMissingControlItemsWithoutRecovery() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.missing", title: "Missing"),
            windowID: 318
        )
        var observedContexts = [String]()
        var didReportMissingControls = false

        let outcome = await MenuBarLayoutResetExecutor.execute(
            alwaysHiddenSectionEnabled: false,
            controlItemWindowIDs: .unresolved,
            operations: MenuBarLayoutResetExecutor.Operations(
                observeItems: { context in
                    observedContexts.append(context)
                    return [item]
                },
                setAlwaysHiddenSectionEnabled: { _ in
                    XCTFail("Always-hidden toggle should not run when recovery is disabled")
                },
                enforceControlItemOrder: { _ in
                    XCTFail("Control order cannot be enforced without controls")
                },
                moveItem: { _, _ in
                    XCTFail("Move should not run without controls")
                },
                boundsForItem: { item in item.bounds },
                sleep: { _ in
                    XCTFail("Recovery sleeps should not run when recovery is disabled")
                }
            ),
            diagnostics: MenuBarLayoutResetExecutor.Diagnostics(
                recordMissingControlItems: {
                    didReportMissingControls = true
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarLayoutResetExecutor.Outcome(
                firstPassMoveCount: 0,
                firstPassFailureCount: 0,
                secondPassMoveCount: 0,
                failedMoveCount: 0,
                controlRecoveryAttempted: false,
                stopReason: .controlItemsMissing
            )
        )
        XCTAssertTrue(didReportMissingControls)
        XCTAssertEqual(observedContexts, ["layoutResetInitial"])
    }

    @MainActor
    func testLayoutResetFinalizerRunsImmediateImageRefreshAfterCacheRebuild() async {
        var events = [String]()
        var backgroundContinuation: CheckedContinuation<Void, Never>?

        let outcome = await MenuBarLayoutResetFinalizer.execute(
            operations: MenuBarLayoutResetFinalizer.Operations(
                clearCacheLedger: {
                    events.append("clear-ledger")
                },
                resetItemCache: {
                    events.append("reset-cache")
                },
                storeBackgroundContinuation: { continuation in
                    events.append("store-continuation")
                    backgroundContinuation = continuation
                },
                startCacheRebuild: {
                    events.append("start-rebuild")
                    backgroundContinuation?.resume()
                    backgroundContinuation = nil
                },
                clearNewItemSuppression: {
                    events.append("clear-suppression")
                },
                clearImageCache: {
                    events.append("clear-images")
                },
                cleanupImageCache: {
                    events.append("cleanup-images")
                },
                itemCacheHasDisplayID: {
                    events.append("has-display")
                    return true
                },
                updateImageCache: {
                    events.append("update-images")
                },
                sleep: { _ in
                    XCTFail("Fallback sleep should not run when cache has a display")
                },
                publishChange: {
                    events.append("publish")
                },
                invalidateMenuBarHeightCache: {
                    events.append("invalidate-height")
                }
            )
        )

        XCTAssertEqual(outcome, MenuBarLayoutResetFinalizer.Outcome(imageRefreshPath: .immediate))
        XCTAssertEqual(
            events,
            [
                "clear-ledger",
                "reset-cache",
                "store-continuation",
                "start-rebuild",
                "clear-suppression",
                "clear-images",
                "cleanup-images",
                "has-display",
                "update-images",
                "publish",
                "invalidate-height",
            ]
        )
    }

    @MainActor
    func testLayoutResetFinalizerWaitsBeforeImageRefreshWhenCacheHasNoDisplay() async {
        var events = [String]()
        var sleepDurations = [Duration]()
        var backgroundContinuation: CheckedContinuation<Void, Never>?

        let outcome = await MenuBarLayoutResetFinalizer.execute(
            operations: MenuBarLayoutResetFinalizer.Operations(
                clearCacheLedger: {
                    events.append("clear-ledger")
                },
                resetItemCache: {
                    events.append("reset-cache")
                },
                storeBackgroundContinuation: { continuation in
                    backgroundContinuation = continuation
                },
                startCacheRebuild: {
                    backgroundContinuation?.resume()
                    backgroundContinuation = nil
                },
                clearNewItemSuppression: {
                    events.append("clear-suppression")
                },
                clearImageCache: {
                    events.append("clear-images")
                },
                cleanupImageCache: {
                    events.append("cleanup-images")
                },
                itemCacheHasDisplayID: {
                    events.append("missing-display")
                    return false
                },
                updateImageCache: {
                    events.append("update-images")
                },
                sleep: { duration in
                    sleepDurations.append(duration)
                    events.append("sleep")
                },
                publishChange: {
                    events.append("publish")
                },
                invalidateMenuBarHeightCache: {
                    events.append("invalidate-height")
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarLayoutResetFinalizer.Outcome(imageRefreshPath: .fallbackAfterCacheMiss)
        )
        XCTAssertEqual(
            sleepDurations,
            [MenuBarLayoutResetPolicy.delay(after: .cacheFallbackSettle)]
        )
        XCTAssertEqual(
            events,
            [
                "clear-ledger",
                "reset-cache",
                "clear-suppression",
                "clear-images",
                "cleanup-images",
                "missing-display",
                "sleep",
                "update-images",
                "publish",
                "invalidate-height",
            ]
        )
    }

    func testCacheAdmissionPolicySkipsDuringRecentMoveUnlessExplicitlyBypassed() {
        XCTAssertEqual(
            MenuBarCacheAdmissionPolicy.preGateDecision(
                skipRecentMoveCheck: false,
                recentMoveOccurred: true,
                userIsDraggingMenuBarItem: false
            ),
            .skip(.recentMove)
        )
        XCTAssertEqual(
            MenuBarCacheAdmissionPolicy.preGateDecision(
                skipRecentMoveCheck: true,
                recentMoveOccurred: true,
                userIsDraggingMenuBarItem: false
            ),
            .attemptGate
        )
    }

    func testCacheAdmissionPolicySkipsWhileUserIsDragging() {
        XCTAssertEqual(
            MenuBarCacheAdmissionPolicy.preGateDecision(
                skipRecentMoveCheck: true,
                recentMoveOccurred: true,
                userIsDraggingMenuBarItem: true
            ),
            .skip(.userDragging)
        )
    }

    func testCacheAdmissionPolicyMapsCacheGateResult() {
        XCTAssertEqual(
            MenuBarCacheAdmissionPolicy.gateDecision(cacheGateAcquired: true),
            .run
        )
        XCTAssertEqual(
            MenuBarCacheAdmissionPolicy.gateDecision(cacheGateAcquired: false),
            .skip(.cacheInProgress)
        )
        XCTAssertEqual(MenuBarCacheAdmissionPolicy.recentMoveQuietWindow, .seconds(1))
    }

    func testCacheCyclePolicyPreservesKnownGoodCacheWhenControlItemsAreMissing() {
        XCTAssertEqual(
            MenuBarCacheCyclePolicy.controlItemDecision(controlItemsFound: true),
            .continueCycle
        )
        XCTAssertEqual(
            MenuBarCacheCyclePolicy.controlItemDecision(controlItemsFound: false),
            .preserveKnownGoodCache
        )
    }

    func testCacheCyclePolicySchedulesOneRelocationRecacheWithStablePriority() {
        XCTAssertEqual(
            MenuBarCacheCyclePolicy.relocationFollowUpDecision(
                newLeftmostItemsRelocated: false,
                pendingItemsRelocated: false
            ),
            .continueCycle
        )
        XCTAssertEqual(
            MenuBarCacheCyclePolicy.relocationFollowUpDecision(
                newLeftmostItemsRelocated: true,
                pendingItemsRelocated: false
            ),
            .scheduleRecache(.newLeftmostItems)
        )
        XCTAssertEqual(
            MenuBarCacheCyclePolicy.relocationFollowUpDecision(
                newLeftmostItemsRelocated: false,
                pendingItemsRelocated: true
            ),
            .scheduleRecache(.pendingItems)
        )
        XCTAssertEqual(
            MenuBarCacheCyclePolicy.relocationFollowUpDecision(
                newLeftmostItemsRelocated: true,
                pendingItemsRelocated: true
            ),
            .scheduleRecache(.newLeftmostItems)
        )
    }

    func testCacheCyclePolicySeparatesStartupSettlingFromSavedLayoutApply() {
        XCTAssertEqual(
            MenuBarCacheCyclePolicy.postRelocationDecision(
                isInStartupSettling: true,
                skipSavedLayoutApply: false
            ),
            .cacheObservation(.startupSettling)
        )
        XCTAssertEqual(
            MenuBarCacheCyclePolicy.postRelocationDecision(
                isInStartupSettling: false,
                skipSavedLayoutApply: true
            ),
            .cacheObservation(.savedLayoutApplySkipped)
        )
        XCTAssertEqual(
            MenuBarCacheCyclePolicy.postRelocationDecision(
                isInStartupSettling: false,
                skipSavedLayoutApply: false
            ),
            .evaluateSavedLayout
        )
    }

    func testCacheCyclePolicyRecordsSourcePIDBaselineOnlyAfterResolvedObservations() {
        XCTAssertTrue(MenuBarCacheCyclePolicy.shouldRecordResolvedSourcePIDs(resolveSourcePID: true))
        XCTAssertFalse(MenuBarCacheCyclePolicy.shouldRecordResolvedSourcePIDs(resolveSourcePID: false))
    }

    @MainActor
    func testCacheCycleContinuationSchedulesRecacheAfterNewLeftmostRelocation() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.new", title: "New"),
            windowID: 430,
            sourcePID: 9_001
        )
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 100, y: 0, width: 10, height: 22)
        )
        var events = [String]()
        var scheduledReasons = [MenuBarCacheCyclePolicy.RelocationReason]()

        let outcome = await MenuBarCacheCycleContinuationExecutor.execute(
            input: MenuBarCacheCycleContinuationExecutor.Input(
                items: [item],
                controlItems: controlItems,
                previousWindowIDs: [],
                previousDisplayID: 1,
                currentDisplayID: 2,
                isInStartupSettling: false,
                skipSavedLayoutApply: false,
                resolveSourcePID: true
            ),
            operations: MenuBarCacheCycleContinuationExecutor.Operations(
                taskIsCancelled: { false },
                enforceControlItemOrder: { _ in
                    events.append("order")
                },
                relocateNewLeftmostItems: { _, _, _ in
                    events.append("new-leftmost")
                    return true
                },
                relocatePendingItems: { _, _ in
                    XCTFail("Pending relocation should not run after new-leftmost recache scheduling")
                    return false
                },
                scheduleFollowUpRecache: { reason in
                    scheduledReasons.append(reason)
                    events.append("schedule")
                },
                cacheObservation: { _, _, _ in
                    XCTFail("Cache commit should not run when a follow-up recache is scheduled")
                },
                applySavedLayout: { _, _, _, _, _ in
                    XCTFail("Saved layout should not run when a follow-up recache is scheduled")
                    return false
                },
                recordResolvedSourcePIDs: { _ in
                    XCTFail("Source PID baseline should not update before the follow-up recache")
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarCacheCycleContinuationExecutor.Outcome(
                stopReason: .followUpRecacheScheduled(.newLeftmostItems)
            )
        )
        XCTAssertEqual(events, ["order", "new-leftmost", "schedule"])
        XCTAssertEqual(scheduledReasons, [.newLeftmostItems])
    }

    @MainActor
    func testCacheCycleContinuationCachesObservationDuringStartupSettling() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.startup", title: "Startup"),
            windowID: 431,
            sourcePID: 9_002
        )
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 100, y: 0, width: 10, height: 22)
        )
        var events = [String]()

        let outcome = await MenuBarCacheCycleContinuationExecutor.execute(
            input: MenuBarCacheCycleContinuationExecutor.Input(
                items: [item],
                controlItems: controlItems,
                previousWindowIDs: [400],
                previousDisplayID: 1,
                currentDisplayID: 2,
                isInStartupSettling: true,
                skipSavedLayoutApply: false,
                resolveSourcePID: true
            ),
            operations: MenuBarCacheCycleContinuationExecutor.Operations(
                taskIsCancelled: { false },
                enforceControlItemOrder: { _ in
                    events.append("order")
                },
                relocateNewLeftmostItems: { _, _, _ in
                    events.append("new-leftmost")
                    return false
                },
                relocatePendingItems: { _, _ in
                    events.append("pending")
                    return false
                },
                scheduleFollowUpRecache: { _ in
                    XCTFail("No follow-up recache should be scheduled")
                },
                cacheObservation: { _, _, displayID in
                    events.append("cache:\(displayID ?? 0)")
                },
                applySavedLayout: { _, _, _, _, _ in
                    XCTFail("Saved layout should be skipped during startup settling")
                    return false
                },
                recordResolvedSourcePIDs: { _ in
                    XCTFail("Source PID baseline should not update during startup settling")
                }
            ),
            diagnostics: MenuBarCacheCycleContinuationExecutor.Diagnostics(
                recordStartupSettlingCached: {
                    events.append("startup")
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarCacheCycleContinuationExecutor.Outcome(
                stopReason: .cachedObservation(.startupSettling)
            )
        )
        XCTAssertEqual(events, ["order", "new-leftmost", "pending", "cache:2", "startup"])
    }

    @MainActor
    func testCacheCycleContinuationSkipsSavedLayoutButCommitsCacheAndPIDBaseline() async {
        let resolvedItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.resolved", title: "Resolved"),
            windowID: 432,
            sourcePID: 9_003
        )
        let unresolvedItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.unresolved", title: "Unresolved"),
            windowID: 433,
            sourcePID: nil
        )
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 100, y: 0, width: 10, height: 22)
        )
        var events = [String]()
        var recordedPIDs = [CGWindowID: pid_t]()

        let outcome = await MenuBarCacheCycleContinuationExecutor.execute(
            input: MenuBarCacheCycleContinuationExecutor.Input(
                items: [resolvedItem, unresolvedItem],
                controlItems: controlItems,
                previousWindowIDs: [401],
                previousDisplayID: 1,
                currentDisplayID: 2,
                isInStartupSettling: false,
                skipSavedLayoutApply: true,
                resolveSourcePID: true
            ),
            operations: MenuBarCacheCycleContinuationExecutor.Operations(
                taskIsCancelled: { false },
                enforceControlItemOrder: { _ in
                    events.append("order")
                },
                relocateNewLeftmostItems: { _, _, _ in
                    events.append("new-leftmost")
                    return false
                },
                relocatePendingItems: { _, _ in
                    events.append("pending")
                    return false
                },
                scheduleFollowUpRecache: { _ in
                    XCTFail("No follow-up recache should be scheduled")
                },
                cacheObservation: { _, _, displayID in
                    events.append("cache:\(displayID ?? 0)")
                },
                applySavedLayout: { _, _, _, _, _ in
                    XCTFail("Saved layout should not be evaluated when explicitly skipped")
                    return false
                },
                recordResolvedSourcePIDs: { pids in
                    recordedPIDs = pids
                    events.append("record-pids")
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarCacheCycleContinuationExecutor.Outcome(stopReason: .committedCache)
        )
        XCTAssertEqual(events, ["order", "new-leftmost", "pending", "cache:2", "record-pids"])
        XCTAssertEqual(recordedPIDs, [resolvedItem.windowID: 9_003])
    }

    @MainActor
    func testCacheCycleContinuationStopsWhenSavedLayoutWasApplied() async {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.restore", title: "Restore"),
            windowID: 434,
            sourcePID: 9_004
        )
        let controlItems = MenuBarControlItems.fixture(
            hiddenAt: CGRect(x: 100, y: 0, width: 10, height: 22)
        )
        var events = [String]()

        let outcome = await MenuBarCacheCycleContinuationExecutor.execute(
            input: MenuBarCacheCycleContinuationExecutor.Input(
                items: [item],
                controlItems: controlItems,
                previousWindowIDs: [402],
                previousDisplayID: 1,
                currentDisplayID: 2,
                isInStartupSettling: false,
                skipSavedLayoutApply: false,
                resolveSourcePID: true
            ),
            operations: MenuBarCacheCycleContinuationExecutor.Operations(
                taskIsCancelled: { false },
                enforceControlItemOrder: { _ in
                    events.append("order")
                },
                relocateNewLeftmostItems: { _, _, _ in
                    events.append("new-leftmost")
                    return false
                },
                relocatePendingItems: { _, _ in
                    events.append("pending")
                    return false
                },
                scheduleFollowUpRecache: { _ in
                    XCTFail("No follow-up recache should be scheduled")
                },
                cacheObservation: { _, _, _ in
                    XCTFail("Final cache commit should not run after saved layout applies")
                },
                applySavedLayout: { _, previousWindowIDs, _, previousDisplayID, currentDisplayID in
                    events.append(
                        "apply:\(previousWindowIDs.first ?? 0):\(previousDisplayID ?? 0):\(currentDisplayID ?? 0)"
                    )
                    return true
                },
                recordResolvedSourcePIDs: { _ in
                    XCTFail("Source PID baseline should not update after saved layout applies")
                }
            )
        )

        XCTAssertEqual(
            outcome,
            MenuBarCacheCycleContinuationExecutor.Outcome(stopReason: .savedLayoutApplied)
        )
        XCTAssertEqual(events, ["order", "new-leftmost", "pending", "apply:402:1:2"])
    }

    func testObservationFrameDropsCloneWindowsAndNormalizesWindowIDs() {
        let clone = MenuBarItem.fixture(
            tag: MenuBarItemTag(
                namespace: .string("Window Server"),
                title: "System Status Item Clone",
                windowID: 90
            ),
            windowID: 90,
            sourcePID: nil,
            ownerPID: 88
        )
        let first = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.first", title: "First"),
            windowID: 91,
            sourcePID: 1234
        )
        let second = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.second", title: "Second"),
            windowID: 92,
            sourcePID: 1235
        )

        let frame = MenuBarObservationFrame.filteringSystemClones(
            displayID: 126,
            rawItems: [clone, first, second],
            currentItemWindowIDs: [92, 90, 91]
        )

        XCTAssertEqual(frame.items.map(\.windowID), [91, 92])
        XCTAssertEqual(frame.cloneCount, 1)
        XCTAssertEqual(frame.droppedCloneWindowIDs, [90])
        XCTAssertEqual(frame.normalizedWindowIDs, [92, 91])
        XCTAssertEqual(frame.droppedCloneDescriptions, [clone.tag.description])
    }

    func testObservationFrameDefaultWindowIDsFollowFilteredMenuBarOrder() {
        let first = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.first", title: "First"),
            windowID: 93,
            sourcePID: 1234
        )
        let second = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.second", title: "Second"),
            windowID: 94,
            sourcePID: 1235
        )

        let frame = MenuBarObservationFrame.filteringSystemClones(
            displayID: 126,
            rawItems: [first, second]
        )

        XCTAssertEqual(frame.normalizedWindowIDs, [94, 93])
    }

    func testObservationFramePersistableIdentifiersOnlyIncludesStablePreviouslySeenItems() {
        let stable = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.stable", title: "Stable"),
            windowID: 95,
            sourcePID: 1234
        )
        let unresolved = MenuBarItem.fixture(
            tag: MenuBarItemTag(
                namespace: .controlCenter,
                title: "Item-0",
                windowID: 96
            ),
            windowID: 96,
            sourcePID: nil,
            ownerPID: 999,
            title: "Item-0"
        )
        let structural = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 97,
            sourcePID: nil
        )
        let unseenStable = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.unseen", title: "Unseen"),
            windowID: 98,
            sourcePID: 1235
        )
        let frame = MenuBarObservationFrame(
            displayID: 126,
            items: [stable, unresolved, structural, unseenStable]
        )

        XCTAssertEqual(
            frame.persistableIdentifiersForPreviouslySeenWindows([95, 96, 97]),
            ["com.example.stable:Stable"]
        )
    }

    func testKnownItemIdentifierPolicyBuildsPersistableBaseIdentifiers() {
        let stable = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.stable", title: "Stable"),
            windowID: 99,
            sourcePID: 1234
        )
        let unresolved = MenuBarItem.fixture(
            tag: MenuBarItemTag(
                namespace: .controlCenter,
                title: "Item-0",
                windowID: 100
            ),
            windowID: 100,
            sourcePID: nil,
            ownerPID: 999,
            title: "Item-0"
        )
        let control = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 101,
            sourcePID: nil
        )

        XCTAssertEqual(
            MenuBarKnownItemIdentifierPolicy.persistableBaseIdentifiers(
                from: [stable, unresolved, control]
            ),
            ["com.example.stable:Stable"]
        )
    }

    func testKnownItemIdentifierPolicySeedsOnlyPreviouslySeenUnknownIdentifiers() {
        let known = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.known", title: "Known"),
            windowID: 102,
            sourcePID: 1234
        )
        let corrected = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.corrected", title: "Corrected"),
            windowID: 103,
            sourcePID: 1235
        )
        let unseen = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.unseen", title: "Unseen"),
            windowID: 104,
            sourcePID: 1236
        )
        let frame = MenuBarObservationFrame(
            displayID: 126,
            items: [known, corrected, unseen]
        )

        XCTAssertEqual(
            MenuBarKnownItemIdentifierPolicy.identifiersToSeedAfterIdentityCorrection(
                observation: frame,
                previousWindowIDs: [102, 103],
                knownItemIdentifiers: ["com.example.known:Known"]
            ),
            ["com.example.corrected:Corrected"]
        )
    }

    func testKnownItemLedgerLoadsAndPersistsStableSortedSnapshot() {
        var ledger = MenuBarKnownItemLedger()

        ledger.load(["com.example.z:Zed", "com.example.a:Alpha"])

        XCTAssertEqual(ledger.count, 2)
        XCTAssertEqual(
            ledger.persistenceSnapshot,
            ["com.example.a:Alpha", "com.example.z:Zed"]
        )
        XCTAssertTrue(ledger.tracksMenuBarItem(bundleID: "com.example.a"))
        XCTAssertFalse(ledger.tracksMenuBarItem(bundleID: "com.example"))
    }

    func testKnownItemLedgerArmsFirstLaunchSuppressionOnlyWhenEmpty() {
        var empty = MenuBarKnownItemLedger()
        var populated = MenuBarKnownItemLedger()

        populated.load(["com.example.status:Status"])
        empty.armFirstLaunchSuppressionIfEmpty()
        populated.armFirstLaunchSuppressionIfEmpty()

        XCTAssertTrue(empty.suppressesNextNewLeftmostItemRelocation)
        XCTAssertFalse(populated.suppressesNextNewLeftmostItemRelocation)
    }

    func testKnownItemLedgerConsumesRelocationSuppressionBySeedingStableItems() {
        let stable = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.stable", title: "Stable"),
            windowID: 201
        )
        let unresolved = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "Item-0", windowID: 202),
            windowID: 202,
            sourcePID: nil
        )
        var ledger = MenuBarKnownItemLedger()

        ledger.armNextNewLeftmostItemRelocationSuppression()

        XCTAssertTrue(ledger.consumeRelocationSuppressionAndSeed(from: [stable, unresolved]))
        XCTAssertFalse(ledger.suppressesNextNewLeftmostItemRelocation)
        XCTAssertEqual(ledger.identifiers, ["com.example.stable:Stable"])
        XCTAssertFalse(ledger.consumeRelocationSuppressionAndSeed(from: [stable]))
    }

    func testKnownItemLedgerReturnsWhetherRememberChangedState() {
        var ledger = MenuBarKnownItemLedger()

        XCTAssertTrue(ledger.remember("com.example.status:Status"))
        XCTAssertFalse(ledger.remember("com.example.status:Status"))
        XCTAssertFalse(ledger.remember([]))
        XCTAssertTrue(ledger.remember(["com.example.other:Other"]))
        XCTAssertEqual(
            ledger.persistenceSnapshot,
            ["com.example.other:Other", "com.example.status:Status"]
        )
    }

    func testMovePreflightRejectsUnresolvedItems() {
        let item = MenuBarItem.fixture(
            tag: MenuBarItemTag(
                namespace: .controlCenter,
                title: "Item-0",
                windowID: 60
            ),
            windowID: 60,
            sourcePID: nil,
            ownerPID: 999,
            title: "Item-0"
        )

        let decision = MenuBarMovePreflight.evaluate(
            item: item,
            relation: .leftOfItem,
            isBlocked: false
        )

        XCTAssertEqual(decision, .reject(.invalidIdentity(.unresolved)))
    }

    func testMovePreflightAllowsBlockedItemOnlyForVisibleRecovery() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.clock", title: "Clock"),
            windowID: 61,
            sourcePID: 1234
        )

        XCTAssertEqual(
            MenuBarMovePreflight.evaluate(
                item: item,
                relation: .leftOfItem,
                isBlocked: true
            ),
            .reject(.blockedItemRequiresVisibleRecovery)
        )
        XCTAssertEqual(
            MenuBarMovePreflight.evaluate(
                item: item,
                relation: .rightOfItem,
                isBlocked: true
            ),
            .allow
        )
    }

    @MainActor
    func testBlockedItemRecoveryExecutorRestoresCandidatesInOneMoveSession() async {
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_360,
            bounds: CGRect(x: 400, y: 0, width: 32, height: 22),
            sourcePID: nil
        )
        let blocked = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.blocked", title: "Blocked"),
            windowID: 1_361,
            bounds: CGRect(x: -1, y: 0, width: 24, height: 22)
        )
        let visible = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.visible-runtime", title: "Visible"),
            windowID: 1_362,
            bounds: CGRect(x: 120, y: 0, width: 24, height: 22)
        )
        var events = [String]()
        var moved = [(MenuBarItem, MenuBarMoveDestination)]()
        var successes = [String]()
        var sleepDurations = [Duration]()

        let outcome = await MenuBarBlockedItemRecoveryExecutor.execute(
            items: [blocked, visible, hiddenControl],
            controlItemWindowIDs: MenuBarControlItemWindowIDs(hidden: hiddenControl.windowID),
            currentBoundsForItem: { $0.bounds },
            moveItem: { item, destination in
                moved.append((item, destination))
            },
            beginMoveSession: {
                events.append("begin")
            },
            endMoveSession: {
                events.append("end")
            },
            recordMoveSuccess: { item in
                successes.append(item.uniqueIdentifier)
            },
            recordMoveFailure: { item, error in
                XCTFail("Unexpected move failure for \(item.uniqueIdentifier): \(error)")
            },
            sleepAfterRecovery: { duration in
                sleepDurations.append(duration)
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarBlockedItemRecoveryExecutor.Outcome(
                attemptedCount: 1,
                restoredCount: 1,
                failedCount: 0,
                stopReason: .completed
            )
        )
        XCTAssertEqual(events, ["begin", "end"])
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(moved.first?.0, blocked)
        guard case let .rightOfItem(anchor)? = moved.first?.1 else {
            XCTFail("Expected blocked item to move to the visible side of the hidden control")
            return
        }
        XCTAssertEqual(anchor.uniqueIdentifier, hiddenControl.uniqueIdentifier)
        XCTAssertEqual(successes, [blocked.uniqueIdentifier])
        XCTAssertEqual(sleepDurations, [.milliseconds(200)])
    }

    @MainActor
    func testBlockedItemRecoveryExecutorSkipsMoveSessionWhenNoCandidates() async {
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_370,
            sourcePID: nil
        )
        let visible = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.visible-recovery", title: "Visible"),
            windowID: 1_371,
            bounds: CGRect(x: 120, y: 0, width: 24, height: 22)
        )
        var noCandidatesCalled = false
        var events = [String]()
        var movedCount = 0
        var sleepDurations = [Duration]()

        let outcome = await MenuBarBlockedItemRecoveryExecutor.execute(
            items: [visible, hiddenControl],
            controlItemWindowIDs: MenuBarControlItemWindowIDs(hidden: hiddenControl.windowID),
            currentBoundsForItem: { $0.bounds },
            moveItem: { _, _ in
                movedCount += 1
            },
            recordNoCandidates: {
                noCandidatesCalled = true
            },
            recordCandidatesFound: { count in
                XCTFail("Unexpected blocked item candidates: \(count)")
            },
            beginMoveSession: {
                events.append("begin")
            },
            endMoveSession: {
                events.append("end")
            },
            sleepAfterRecovery: { duration in
                sleepDurations.append(duration)
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarBlockedItemRecoveryExecutor.Outcome(
                attemptedCount: 0,
                restoredCount: 0,
                failedCount: 0,
                stopReason: .noCandidates
            )
        )
        XCTAssertTrue(noCandidatesCalled)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(movedCount, 0)
        XCTAssertTrue(sleepDurations.isEmpty)
    }

    @MainActor
    func testBlockedItemRecoveryExecutorReportsMissingControlItemsForCandidates() async {
        let blocked = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.missing-control", title: "MissingControl"),
            windowID: 1_380,
            bounds: CGRect(x: -1, y: 0, width: 24, height: 22)
        )
        var missingControlCounts = [Int]()
        var events = [String]()
        var movedCount = 0
        var sleepDurations = [Duration]()

        let outcome = await MenuBarBlockedItemRecoveryExecutor.execute(
            items: [blocked],
            controlItemWindowIDs: .unresolved,
            currentBoundsForItem: { $0.bounds },
            moveItem: { _, _ in
                movedCount += 1
            },
            recordControlItemsMissing: { count in
                missingControlCounts.append(count)
            },
            beginMoveSession: {
                events.append("begin")
            },
            endMoveSession: {
                events.append("end")
            },
            sleepAfterRecovery: { duration in
                sleepDurations.append(duration)
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarBlockedItemRecoveryExecutor.Outcome(
                attemptedCount: 1,
                restoredCount: 0,
                failedCount: 1,
                stopReason: .controlItemsMissing
            )
        )
        XCTAssertEqual(missingControlCounts, [1])
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(movedCount, 0)
        XCTAssertTrue(sleepDurations.isEmpty)
    }

    @MainActor
    func testBlockedItemRecoveryExecutorCountsMoveFailures() async {
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 1_390,
            sourcePID: nil
        )
        let blocked = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.failed-recovery", title: "FailedRecovery"),
            windowID: 1_391,
            bounds: CGRect(x: -1, y: 0, width: 24, height: 22)
        )
        var events = [String]()
        var failures = [String]()
        var sleepDurations = [Duration]()

        let outcome = await MenuBarBlockedItemRecoveryExecutor.execute(
            items: [blocked, hiddenControl],
            controlItemWindowIDs: MenuBarControlItemWindowIDs(hidden: hiddenControl.windowID),
            currentBoundsForItem: { $0.bounds },
            moveItem: { _, _ in
                throw MenuBarEventError.cannotComplete
            },
            beginMoveSession: {
                events.append("begin")
            },
            endMoveSession: {
                events.append("end")
            },
            recordMoveSuccess: { item in
                XCTFail("Unexpected move success for \(item.uniqueIdentifier)")
            },
            recordMoveFailure: { item, _ in
                failures.append(item.uniqueIdentifier)
            },
            sleepAfterRecovery: { duration in
                sleepDurations.append(duration)
            }
        )

        XCTAssertEqual(
            outcome,
            MenuBarBlockedItemRecoveryExecutor.Outcome(
                attemptedCount: 1,
                restoredCount: 0,
                failedCount: 1,
                stopReason: .completed
            )
        )
        XCTAssertEqual(events, ["begin", "end"])
        XCTAssertEqual(failures, [blocked.uniqueIdentifier])
        XCTAssertEqual(sleepDurations, [.milliseconds(200)])
    }

    func testBlockedItemRecoveryPolicySelectsOnlyMovableNonControlBlockedItems() {
        let liveBlocked = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.live", title: "Live"),
            windowID: 62,
            bounds: CGRect(x: 120, y: 0, width: 24, height: 22)
        )
        let cachedBlocked = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.cached", title: "Cached"),
            windowID: 63,
            bounds: CGRect(x: -1, y: 0, width: 24, height: 22)
        )
        let visible = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.visible", title: "Visible"),
            windowID: 64,
            bounds: CGRect(x: 300, y: 0, width: 24, height: 22)
        )
        let controlItem = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 65,
            bounds: CGRect(x: -1, y: 0, width: 24, height: 22),
            sourcePID: nil
        )
        let immovableControlCenterItem = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .controlCenter, title: "", windowID: 66),
            windowID: 66,
            bounds: CGRect(x: -1, y: 0, width: 24, height: 22),
            title: ""
        )

        let liveBounds = [
            liveBlocked.windowID: CGRect(x: -1, y: 0, width: 24, height: 22),
            visible.windowID: CGRect(x: 300, y: 0, width: 24, height: 22),
        ]

        let candidates = MenuBarBlockedItemRecoveryPolicy.recoveryCandidates(
            from: [liveBlocked, cachedBlocked, visible, controlItem, immovableControlCenterItem]
        ) { item in
            liveBounds[item.windowID]
        }

        XCTAssertEqual(candidates.map(\.windowID), [liveBlocked.windowID, cachedBlocked.windowID])
    }

    func testBlockedItemRecoveryPolicyRestoresToVisibleSideOfHiddenControl() {
        let hiddenControl = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 67,
            sourcePID: nil
        )

        XCTAssertEqual(
            MenuBarBlockedItemRecoveryPolicy.visibleRecoveryDestination(hiddenControlItem: hiddenControl),
            .rightOfItem(hiddenControl)
        )
    }
}

private extension MenuBarRuntimeTests {
    func savedLayoutSectionItem(
        _ uniqueIdentifier: String,
        currentSection: MenuBarSection.Name?,
        isLayoutItem: Bool = true
    ) -> MenuBarSavedLayoutExecutionPolicy.SectionObservation {
        MenuBarSavedLayoutExecutionPolicy.SectionObservation(
            uniqueIdentifier: uniqueIdentifier,
            currentSection: currentSection,
            isLayoutItem: isLayoutItem
        )
    }

    func savedLayoutSequenceItem(
        _ uniqueIdentifier: String,
        currentSection: MenuBarSection.Name?,
        isLayoutItem: Bool = true
    ) -> MenuBarSavedLayoutSequencePolicy.ItemObservation {
        MenuBarSavedLayoutSequencePolicy.ItemObservation(
            uniqueIdentifier: uniqueIdentifier,
            currentSection: currentSection,
            isLayoutItem: isLayoutItem
        )
    }

    func savedLayoutPreparationSnapshot(
        observedItems: [MenuBarItem],
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    ) -> MenuBarSavedLayoutObservationSnapshot? {
        MenuBarSavedLayoutObservationSnapshot(
            observedItems: observedItems,
            controlItemWindowIDs: .init(),
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder,
            makeSectionLookupContext: { controlItems in
                MenuBarSectionLookupContext(
                    controlItems: controlItems,
                    currentBoundsForItem: { $0.bounds }
                )
            }
        )
    }

    func sectionTransitionItem(
        _ uniqueIdentifier: String,
        windowID: CGWindowID,
        isLayoutItem: Bool = true
    ) -> MenuBarSectionTransitionPolicy.SectionObservation {
        MenuBarSectionTransitionPolicy.SectionObservation(
            uniqueIdentifier: uniqueIdentifier,
            windowID: windowID,
            isLayoutItem: isLayoutItem
        )
    }

    func newItemsPlacement(
        section: String,
        anchor: String? = nil,
        relation: MenuBarNewItemsPlacement.Relation = .sectionDefault
    ) -> MenuBarNewItemsPlacement {
        MenuBarNewItemsPlacement(
            sectionKey: section,
            anchorIdentifier: anchor,
            relation: relation
        )
    }

    func unmanagedPlacementItem(
        _ uniqueIdentifier: String,
        tag: MenuBarItemTag,
        sourcePID: pid_t? = 1234
    ) -> MenuBarUnmanagedPlacementPolicy.ItemObservation {
        MenuBarUnmanagedPlacementPolicy.ItemObservation(
            uniqueIdentifier: uniqueIdentifier,
            tag: tag,
            sourcePID: sourcePID
        )
    }

    func notchBudgetItem(
        _ uniqueIdentifier: String,
        tag: MenuBarItemTag,
        x: CGFloat,
        width: CGFloat,
        isLayoutItem: Bool = false,
        isTransient: Bool = false
    ) -> MenuBarNotchBudgetPolicy.ItemObservation {
        MenuBarNotchBudgetPolicy.ItemObservation(
            uniqueIdentifier: uniqueIdentifier,
            tag: tag,
            bounds: CGRect(x: x, y: 0, width: width, height: 22),
            isLayoutItem: isLayoutItem,
            isTransientControlCenterItem: isTransient
        )
    }

    final class TemporaryRevealExecutorHarness {
        var events = [String]()
        var hasTemporaryContexts = false
        var forceRehideCount = 0
        var outstandingContexts = [MenuBarTemporaryRevealPolicy.OutstandingContext]()
        var observedItems = [MenuBarItem]()
        var shownAlertItems = [MenuBarItem]()
        var recordedMetadataValues = [MenuBarTemporaryRevealPolicy.PendingMetadata]()
        var recordedMetadataTags = [String]()
        var clearedTags = [String]()
        var persistCount = 0
        var windowOriginSequence = [CGPoint?]()
        var moveError: Error?
        var moveDestinations = [MenuBarMoveDestination]()
        var moveAttemptBudgets = [Int?]()
        var appendedContexts = [MenuBarTemporaryRevealContext]()
        var scheduleCount = 0
        var refreshedTargets = [MenuBarItem]()
        var visibleIDs = Set<CGWindowID>()
        var electronItem = false
        var accessibilityPressResult = false
        var clickErrors = [Error]()
        var clickedItems = [MenuBarItem]()
        var clickAttemptBudgets = [Int]()

        func operations() -> MenuBarTemporaryRevealExecutor.Operations {
            MenuBarTemporaryRevealExecutor.Operations(
                hasTemporaryContexts: {
                    self.events.append("hasContexts")
                    return self.hasTemporaryContexts
                },
                cancelRehideTriggers: {
                    self.events.append("cancel")
                },
                forceRehideExistingContexts: {
                    self.events.append("forceRehide")
                    self.forceRehideCount += 1
                },
                outstandingContexts: {
                    self.events.append("outstanding")
                    return self.outstandingContexts
                },
                removeExistingContext: { tag in
                    self.events.append("remove")
                    self.clearedTags.append(tag.tagIdentifier)
                },
                scheduleRehideTimer: {
                    self.events.append("timer")
                    self.scheduleCount += 1
                },
                observeItems: { displayID in
                    self.events.append("observe-\(displayID)")
                    return self.observedItems
                },
                showNoRoomAlert: { item in
                    self.events.append("alert")
                    self.shownAlertItems.append(item)
                },
                recordPendingMetadata: { metadata, tagIdentifier in
                    self.events.append("recordPending")
                    self.recordedMetadataValues.append(metadata)
                    self.recordedMetadataTags.append(tagIdentifier)
                },
                clearPendingRelocation: { tagIdentifier in
                    self.events.append("clear")
                    self.clearedTags.append(tagIdentifier)
                },
                persistPendingRelocations: {
                    self.events.append("persist")
                    self.persistCount += 1
                },
                beginInputSession: {
                    self.events.append("begin")
                },
                endInputSession: {
                    self.events.append("end")
                },
                windowOrigin: { _ in
                    self.events.append("origin")
                    guard !self.windowOriginSequence.isEmpty else {
                        return nil
                    }
                    return self.windowOriginSequence.removeFirst()
                },
                moveItem: { _, destination, _, maxAttempts in
                    self.events.append("move-\(maxAttempts.map(String.init) ?? "nil")")
                    self.moveDestinations.append(destination)
                    self.moveAttemptBudgets.append(maxAttempts)
                    if let moveError = self.moveError {
                        throw moveError
                    }
                },
                appendContext: { context in
                    self.events.append("append")
                    self.appendedContexts.append(context)
                },
                waitForItemToLeaveOrigin: { _, _, _ in
                    self.events.append("leaveOrigin")
                },
                waitForItemPositionToSettle: { _ in
                    self.events.append("settle")
                },
                refreshedClickTarget: { item, _ in
                    self.events.append("refresh")
                    guard !self.refreshedTargets.isEmpty else {
                        return item
                    }
                    return self.refreshedTargets.removeFirst()
                },
                sleep: { _ in
                    self.events.append("sleep")
                },
                visibleWindowIDs: {
                    self.events.append("ids")
                    return self.visibleIDs
                },
                isElectronItem: { _ in
                    self.events.append("electron")
                    return self.electronItem
                },
                pressItemViaAccessibility: { _ in
                    self.events.append("pressAX")
                    return self.accessibilityPressResult
                },
                clickItem: { item, _, maxAttempts in
                    self.events.append("click-\(maxAttempts)")
                    self.clickedItems.append(item)
                    self.clickAttemptBudgets.append(maxAttempts)
                    if !self.clickErrors.isEmpty {
                        throw self.clickErrors.removeFirst()
                    }
                },
                shownInterfaceWindow: { _, _ in
                    self.events.append("window")
                    return nil
                }
            )
        }
    }

    func temporaryRevealContext(
        tag: MenuBarItemTag = .appItem(bundleID: "com.example.item", title: "Item", windowID: 101),
        sourcePID: pid_t = 1234,
        displayID: CGDirectDisplayID = 1,
        target: MenuBarItem? = nil,
        fallback: MenuBarItem? = nil,
        originalSection: MenuBarSection.Name = .hidden
    ) -> MenuBarTemporaryRevealContext {
        let target = target ?? MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.target", title: "Target", windowID: 102),
            windowID: 102,
            sourcePID: 1235
        )
        let fallbackNeighbor = fallback.map {
            MenuBarTemporaryRevealPolicy.Neighbor(
                tag: $0.tag,
                pid: $0.sourcePID ?? $0.ownerPID
            )
        }
        let route = MenuBarTemporaryRevealPolicy.ReturnRoute(
            destination: .leftOfItem(target),
            fallbackNeighbor: fallbackNeighbor,
            originalSection: originalSection
        )
        return MenuBarTemporaryRevealContext(
            tag: tag,
            sourcePID: sourcePID,
            displayID: displayID,
            returnRoute: route
        )
    }

    func emptyPendingRelocationPlanningInput() -> PendingLedger.RelocationPlanningInput {
        PendingLedger.RelocationPlanningInput(
            activelyShownTags: [],
            returnInfo: PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        )
    }

    func popupObservation(
        ownerPID: pid_t = 1234,
        layer: Int,
        height: CGFloat = 80,
        isOnScreen: Bool = true,
        appActivationPolicy: NSApplication.ActivationPolicy? = nil,
        appIsActive: Bool? = nil
    ) -> MenuBarPopupVisibilityPolicy.WindowObservation {
        MenuBarPopupVisibilityPolicy.WindowObservation(
            ownerPID: ownerPID,
            layer: layer,
            bounds: CGRect(x: 0, y: 0, width: 160, height: height),
            isOnScreen: isOnScreen,
            appActivationPolicy: appActivationPolicy,
            appIsActive: appIsActive
        )
    }

    func menuOpenItem(
        windowID: CGWindowID,
        ownerPID: pid_t = 1234,
        sourcePID: pid_t? = 1234,
        ownerBundleIdentifier: String? = "com.example.status",
        isControlItem: Bool = false,
        isOnScreen: Bool = true
    ) -> MenuBarMenuOpenProbePolicy.ItemObservation {
        MenuBarMenuOpenProbePolicy.ItemObservation(
            windowID: windowID,
            ownerPID: ownerPID,
            sourcePID: sourcePID,
            ownerBundleIdentifier: ownerBundleIdentifier,
            isControlItem: isControlItem,
            isOnScreen: isOnScreen
        )
    }

    func menuOpenWindow(
        windowID: CGWindowID,
        ownerPID: pid_t = 4321,
        ownerBundleIdentifier: String? = "com.example.status",
        title: String? = nil,
        isMenuRelated: Bool = true
    ) -> MenuBarMenuOpenProbePolicy.WindowObservation {
        MenuBarMenuOpenProbePolicy.WindowObservation(
            windowID: windowID,
            ownerPID: ownerPID,
            ownerBundleIdentifier: ownerBundleIdentifier,
            title: title,
            isMenuRelated: isMenuRelated
        )
    }
}
