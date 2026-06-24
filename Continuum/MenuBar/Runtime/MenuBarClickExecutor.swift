//
//  MenuBarClickExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Executes one bounded synthetic click session.
///
/// Low-level CGEvent construction remains at the platform edge. This executor
/// owns the session contract around it: input quieting, HID pause/resume, retry
/// budget, retry pacing, and error normalization.
enum MenuBarClickExecutor {
    struct Outcome: Equatable {
        let attemptCount: Int
    }

    @MainActor
    static func execute(
        item: MenuBarItem,
        mouseButton: CGMouseButton,
        skipInputPause: Bool,
        maxAttempts: Int,
        waitForUserToPauseInput: () async throws -> Void,
        beginInputSession: () -> Void,
        endInputSession: () -> Void,
        postClickEvents: (MenuBarItem, CGMouseButton) async throws -> Void,
        sleepAfterFailedAttempt: () async -> Void,
        now: () -> Date = { Date.now },
        recordClickStart: (MenuBarItem, CGMouseButton) -> Void = { _, _ in },
        recordAttemptSuccess: (Int, TimeInterval) -> Void = { _, _ in },
        recordAttemptFailure: (Int, TimeInterval, Error) -> Void = { _, _, _ in }
    ) async throws -> Outcome {
        if !skipInputPause {
            try await waitForUserToPauseInput()
        }

        recordClickStart(item, mouseButton)

        beginInputSession()
        defer {
            endInputSession()
        }

        let attemptStartTime = now()
        var execution = MenuBarClickExecution(maxAttempts: maxAttempts)
        while let attempt = execution.beginAttempt() {
            guard !Task.isCancelled else {
                throw MenuBarEventError.cannotComplete
            }

            do {
                let clickStartTime = now()
                try await postClickEvents(item, mouseButton)
                recordAttemptSuccess(attempt, now().timeIntervalSince(clickStartTime))
                return Outcome(attemptCount: attempt)
            } catch {
                recordAttemptFailure(
                    attempt,
                    now().timeIntervalSince(attemptStartTime),
                    error
                )
                if execution.continuationAfterFailedAttempt() == .retry {
                    await sleepAfterFailedAttempt()
                    continue
                }
                if error is MenuBarEventError {
                    throw error
                }
                throw MenuBarEventError.cannotComplete
            }
        }

        throw MenuBarEventError.cannotComplete
    }
}
