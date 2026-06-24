//
//  MenuBarMoveSessionExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Executes one high-level menu bar move session.
///
/// The manager still owns live CGEvent posting, HID monitors, cursor primitives,
/// and WindowServer bounds reads. This executor owns the stable runtime sequence
/// around those edges: preflight, input pacing, HID suspension, cursor lifetime,
/// retry attempts, destination verification, blocked-item validation, and
/// operation-failure reporting.
enum MenuBarMoveSessionExecutor {
    enum StopReason: Equatable {
        case noOp(MenuBarMovePreflight.RejectionReason)
        case alreadyAtDestination
        case acceptedPositionMatch
        case verifiedAfterEvents
    }

    struct Outcome: Equatable {
        let attempts: Int
        let observedDisplacement: Bool
        let stopReason: StopReason
    }

    struct Operations {
        let taskIsCancelled: () -> Bool
        let waitForUserToPauseInput: () async throws -> Void
        let stopHIDEvents: () -> Void
        let startHIDEvents: () -> Void
        let waitForMoveOperationBuffer: () async throws -> Void
        let itemHasCorrectPosition: (MenuBarMoveCommand, CGDirectDisplayID) async throws -> Bool
        let shouldManageCursor: () -> Bool
        let mouseLocation: () throws -> CGPoint
        let hideCursor: (DispatchTimeInterval) -> Void
        let warpCursor: (CGPoint) -> Void
        let showCursor: () -> Void
        let postMoveEvents: (MenuBarMoveCommand, CGDirectDisplayID) async throws -> Void
        let validateItemPositionAfterMove: (MenuBarMoveCommand, CGDirectDisplayID) async -> Void
        let recordOperationFailure: (String) -> Void
    }

    struct Diagnostics {
        var recordBlockedMoveAllowed: (MenuBarItem) -> Void = { _ in }
        var recordNoOp: (MenuBarItem, MenuBarMovePreflight.RejectionReason) -> Void = { _, _ in }
        var recordRejected: (MenuBarItem, MenuBarMovePreflight.RejectionReason) -> Void = { _, _ in }
        var recordMoveStart: (MenuBarMoveCommand, CGDirectDisplayID) -> Void = { _, _ in }
        var recordAlreadyAtDestination: () -> Void = {}
        var recordAcceptedPositionMatch: () -> Void = {}
        var recordPossibleFalsePositive: (Int) -> Void = { _ in }
        var recordAttemptVerified: (Int) -> Void = { _ in }
        var recordAttemptUnverified: (Int) -> Void = { _ in }
        var recordAttemptFailed: (Int, Error) -> Void = { _, _ in }
        var recordAttemptsExhausted: (MenuBarMoveExecution) -> Void = { _ in }
    }

    @MainActor
    static func execute(
        command: MenuBarMoveCommand,
        itemIsBlocked: Bool,
        resolvedDisplayID: CGDirectDisplayID,
        operations: Operations,
        diagnostics: Diagnostics = Diagnostics()
    ) async throws -> Outcome {
        switch command.preflight(isBlocked: itemIsBlocked) {
        case .allow:
            if itemIsBlocked {
                diagnostics.recordBlockedMoveAllowed(command.item)
            }
        case let .noOp(reason):
            diagnostics.recordNoOp(command.item, reason)
            return Outcome(attempts: 0, observedDisplacement: false, stopReason: .noOp(reason))
        case let .reject(reason):
            diagnostics.recordRejected(command.item, reason)
            operations.recordOperationFailure(
                "Move rejected: \(command.diagnosticDescription), reason=\(reason)"
            )
            if reason == .itemNotMovable {
                throw MenuBarEventError.itemNotMovable(command.item)
            }
            throw MenuBarEventError.cannotComplete
        }

        if !command.skipInputPause {
            try await operations.waitForUserToPauseInput()
        }

        operations.stopHIDEvents()
        defer {
            operations.startHIDEvents()
        }

        try await operations.waitForMoveOperationBuffer()
        diagnostics.recordMoveStart(command, resolvedDisplayID)

        guard try await !operations.itemHasCorrectPosition(command, resolvedDisplayID) else {
            diagnostics.recordAlreadyAtDestination()
            return Outcome(
                attempts: 0,
                observedDisplacement: false,
                stopReason: .alreadyAtDestination
            )
        }

        let manageCursor = operations.shouldManageCursor()
        let originalMouseLocation: CGPoint = manageCursor ? try operations.mouseLocation() : .zero
        if manageCursor {
            operations.hideCursor(command.watchdogTimeout ?? .seconds(10))
        }
        defer {
            if manageCursor {
                operations.warpCursor(originalMouseLocation)
                operations.showCursor()
            }
        }

        var execution = MenuBarMoveExecution(command: command)
        while let attempt = execution.beginAttempt() {
            guard !operations.taskIsCancelled() else {
                throw MenuBarEventError.cannotComplete
            }

            do {
                if try await operations.itemHasCorrectPosition(command, resolvedDisplayID) {
                    switch execution.positionMatchDecision() {
                    case .accept:
                        diagnostics.recordAcceptedPositionMatch()
                        return Outcome(
                            attempts: attempt,
                            observedDisplacement: execution.observedDisplacement,
                            stopReason: .acceptedPositionMatch
                        )
                    case .retryAsPossibleFalsePositive:
                        diagnostics.recordPossibleFalsePositive(attempt)
                    }
                }

                try await operations.postMoveEvents(command, resolvedDisplayID)
                execution.recordObservedDisplacement()

                if try await operations.itemHasCorrectPosition(command, resolvedDisplayID) {
                    diagnostics.recordAttemptVerified(attempt)
                    await operations.validateItemPositionAfterMove(command, resolvedDisplayID)
                    return Outcome(
                        attempts: attempt,
                        observedDisplacement: true,
                        stopReason: .verifiedAfterEvents
                    )
                }

                diagnostics.recordAttemptUnverified(attempt)
                if execution.continuationAfterUnverifiedAttempt() == .retry {
                    try await operations.waitForMoveOperationBuffer()
                    continue
                }
            } catch {
                diagnostics.recordAttemptFailed(attempt, error)
                if execution.continuationAfterFailedAttempt() == .retry {
                    try await operations.waitForMoveOperationBuffer()
                    continue
                }
                operations.recordOperationFailure(
                    execution.failedAttemptDetail(error: error)
                )
                if error is MenuBarEventError {
                    throw error
                }
                throw MenuBarEventError.cannotComplete
            }
        }

        await operations.validateItemPositionAfterMove(command, resolvedDisplayID)
        operations.recordOperationFailure(execution.exhaustedAttemptsDetail())
        diagnostics.recordAttemptsExhausted(execution)
        throw MenuBarEventError.cannotComplete
    }
}
