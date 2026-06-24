//
//  MenuBarInitialCacheExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Executes the non-blocking fast cache warm-up used during setup.
///
/// The first cache pass intentionally skips source-PID resolution so setup can
/// discover control items quickly. Once that fast path succeeds, the executor
/// asks the manager to schedule an authoritative refresh on the normal
/// coalesced refresh lane instead of spawning an untracked task.
enum MenuBarInitialCacheExecutor {
    enum Outcome: Equatable {
        case completed(attempts: Int, succeeded: Bool)
        case cancelled
    }

    struct Operations {
        let runFastCache: () async -> Bool
        let scheduleAuthoritativeRefresh: () -> Void
        let sleepBeforeRetry: () async throws -> Void
    }

    struct Diagnostics {
        var recordStart: () -> Void = {}
        var recordRetryNeeded: (Int) -> Void = { _ in }
        var recordRetrySuccess: (Int) -> Void = { _ in }
    }

    @MainActor
    static func execute(
        operations: Operations,
        diagnostics: Diagnostics = Diagnostics(),
        attempts: ClosedRange<Int> = MenuBarRuntimeRefreshPolicy.initialCacheAttempts
    ) async -> Outcome {
        diagnostics.recordStart()

        for attempt in attempts {
            guard !Task.isCancelled else {
                return .cancelled
            }

            let succeeded = await operations.runFastCache()
            if succeeded {
                if attempt > attempts.lowerBound {
                    diagnostics.recordRetrySuccess(attempt)
                }
                operations.scheduleAuthoritativeRefresh()
                return .completed(attempts: attempt, succeeded: true)
            }

            guard MenuBarRuntimeRefreshPolicy.shouldRetryInitialCache(after: attempt),
                  attempt != attempts.upperBound
            else {
                return .completed(attempts: attempt, succeeded: false)
            }

            diagnostics.recordRetryNeeded(attempt)
            do {
                try await operations.sleepBeforeRetry()
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .cancelled
            }
        }

        return .completed(attempts: 0, succeeded: false)
    }
}
