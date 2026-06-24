//
//  MenuBarTemporaryRehideExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Executes one bounded temporary-rehide session.
///
/// `MenuBarTemporaryRehidePolicy` decides when to start, when to retry, and when
/// to hand recovery to pending relocation. This executor owns the runtime
/// sequence around that policy: draining contexts, observing fresh items,
/// pausing input, moving items, persisting relocation state, and scheduling
/// follow-up work.
enum MenuBarTemporaryRehideExecutor {
    enum StopReason: Equatable {
        case completed
        case deferred
        case observationUnavailable
        case retryQueued
    }

    struct Outcome: Equatable {
        let movedCount: Int
        let failedContextCount: Int
        let handedOffCount: Int
        let stopReason: StopReason
    }

    struct Operations {
        let drainContexts: () -> [MenuBarTemporaryRevealContext]
        let restoreContexts: ([MenuBarTemporaryRevealContext]) -> Void
        let observeItems: () async -> [MenuBarItem]?
        let resolveReturnDestination: (
            MenuBarTemporaryRevealContext,
            [MenuBarItem]
        ) -> MenuBarMoveDestination?
        let moveItem: (
            MenuBarItem,
            MenuBarMoveDestination,
            CGDirectDisplayID
        ) async throws -> Void
        let clearPendingRelocation: (String) -> Void
        let markWaitForRelaunch: (String, String) -> Void
        let persistPendingRelocations: () -> Void
        let appendFailedContextsForRetry: ([MenuBarTemporaryRevealContext]) -> Void
        let scheduleRehideTimer: (TimeInterval) -> Void
        let beginInputSession: () -> Void
        let endInputSession: () -> Void
        let hideCursor: () -> Void
        let showCursor: () -> Void
        let sleepBeforeRehide: (Duration) async -> Void
    }

    struct Diagnostics {
        var recordStart: (Bool, Bool) -> Void = { _, _ in }
        var recordDeferral: (MenuBarTemporaryRehidePolicy.StartDeferralReason) -> Void = { _ in }
        var recordObservationUnavailable: ([MenuBarTemporaryRevealContext]) -> Void = { _ in }
        var recordRehideStart: () -> Void = {}
        var recordMissingItem: (MenuBarTemporaryRevealContext) -> Void = { _ in }
        var recordMissingItemHandOff: (MenuBarTemporaryRevealContext) -> Void = { _ in }
        var recordMissingDestination: (MenuBarTemporaryRevealContext, MenuBarItem) -> Void = { _, _ in }
        var recordMoveSuccess: (
            MenuBarTemporaryRevealContext,
            MenuBarItem,
            MenuBarMoveDestination
        ) -> Void = { _, _, _ in }
        var recordMoveFailure: (
            MenuBarTemporaryRevealContext,
            MenuBarItem,
            Error
        ) -> Void = { _, _, _ in }
        var recordWaitForRelaunch: (MenuBarTemporaryRevealContext, MenuBarItem) -> Void = { _, _ in }
        var recordAllSucceeded: () -> Void = {}
        var recordFailedContexts: ([MenuBarTemporaryRevealContext]) -> Void = { _ in }
    }

    @MainActor
    static func execute(
        force: Bool,
        isCalledFromTemporarilyShow: Bool,
        interfaceIsShowing: Bool,
        userInputPaused: Bool,
        operations: Operations,
        diagnostics: Diagnostics = Diagnostics()
    ) async -> Outcome {
        diagnostics.recordStart(force, isCalledFromTemporarilyShow)

        let startDecision = MenuBarTemporaryRehidePolicy.startDecision(
            force: force,
            interfaceIsShowing: interfaceIsShowing,
            userInputPaused: userInputPaused
        )
        switch startDecision {
        case .proceed:
            break
        case let .reschedule(reason, delay):
            diagnostics.recordDeferral(reason)
            operations.scheduleRehideTimer(delay)
            return Outcome(
                movedCount: 0,
                failedContextCount: 0,
                handedOffCount: 0,
                stopReason: .deferred
            )
        }

        var currentContexts = operations.drainContexts()
        guard !currentContexts.isEmpty else {
            return Outcome(
                movedCount: 0,
                failedContextCount: 0,
                handedOffCount: 0,
                stopReason: .completed
            )
        }

        guard let items = await operations.observeItems() else {
            operations.restoreContexts(currentContexts)
            diagnostics.recordObservationUnavailable(currentContexts)
            if let delay = MenuBarTemporaryRehidePolicy.observationMissRetryDelay(force: force) {
                operations.scheduleRehideTimer(delay)
            }
            return Outcome(
                movedCount: 0,
                failedContextCount: currentContexts.count,
                handedOffCount: 0,
                stopReason: .observationUnavailable
            )
        }

        var failedContexts = [MenuBarTemporaryRevealContext]()
        var movedCount = 0
        var handedOffCount = 0

        operations.beginInputSession()
        defer {
            operations.endInputSession()
        }

        await operations.sleepBeforeRehide(
            MenuBarEventPacingPolicy.rehideSettleDelay(
                isCalledFromTemporarilyShow: isCalledFromTemporarilyShow
            )
        )

        diagnostics.recordRehideStart()

        operations.hideCursor()
        defer {
            operations.showCursor()
        }

        while let context = currentContexts.popLast() {
            guard let item = item(matching: context, in: items) else {
                context.notFoundAttempts += 1
                diagnostics.recordMissingItem(context)

                switch MenuBarTemporaryRehidePolicy.missingItemAction(
                    afterNotFoundAttempts: context.notFoundAttempts
                ) {
                case .keepInMemory:
                    failedContexts.append(context)
                case .giveUpToPendingRelocation:
                    handedOffCount += 1
                    diagnostics.recordMissingItemHandOff(context)
                }
                continue
            }

            guard let destination = operations.resolveReturnDestination(context, items) else {
                handedOffCount += 1
                diagnostics.recordMissingDestination(context, item)
                continue
            }

            do {
                try await operations.moveItem(item, destination, context.displayID)
                operations.clearPendingRelocation(context.tag.tagIdentifier)
                diagnostics.recordMoveSuccess(context, item, destination)
                movedCount += 1
            } catch {
                context.rehideAttempts += 1
                diagnostics.recordMoveFailure(context, item, error)

                switch MenuBarTemporaryRehidePolicy.moveFailureAction(
                    afterRehideAttempts: context.rehideAttempts,
                    windowID: item.windowID,
                    originalSection: context.originalSection
                ) {
                case .retryImmediately:
                    currentContexts.append(context)
                case .retryLater:
                    failedContexts.append(context)
                case let .waitForRelaunch(pendingRelocationValue):
                    operations.markWaitForRelaunch(
                        pendingRelocationValue,
                        context.tag.tagIdentifier
                    )
                    operations.persistPendingRelocations()
                    diagnostics.recordWaitForRelaunch(context, item)
                    handedOffCount += 1
                }
            }
        }

        operations.persistPendingRelocations()

        guard !failedContexts.isEmpty else {
            diagnostics.recordAllSucceeded()
            return Outcome(
                movedCount: movedCount,
                failedContextCount: 0,
                handedOffCount: handedOffCount,
                stopReason: .completed
            )
        }

        diagnostics.recordFailedContexts(failedContexts)
        operations.appendFailedContextsForRetry(failedContexts)
        if let delay = MenuBarTemporaryRehidePolicy.failedContextsRetryDelay(force: force) {
            operations.scheduleRehideTimer(delay)
        }
        return Outcome(
            movedCount: movedCount,
            failedContextCount: failedContexts.count,
            handedOffCount: handedOffCount,
            stopReason: .retryQueued
        )
    }

    private static func item(
        matching context: MenuBarTemporaryRevealContext,
        in items: [MenuBarItem]
    ) -> MenuBarItem? {
        items.first {
            $0.tag.matchesIgnoringWindowID(context.tag) &&
                ($0.sourcePID ?? $0.ownerPID) == context.sourcePID
        }
    }
}
