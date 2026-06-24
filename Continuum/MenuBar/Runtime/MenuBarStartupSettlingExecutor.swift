//
//  MenuBarStartupSettlingExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Executes one startup/app-restart settling window.
///
/// `MenuBarStartupSettlingPolicy` owns the pure polling decisions and
/// `MenuBarStartupSettlingRuntime` owns task handles. This executor owns the
/// runtime sequence around those pieces: wait for initial warm-up, poll until
/// stable or deadline, finish the settling window, then run the two restore
/// cache passes.
enum MenuBarStartupSettlingExecutor {
    struct Observation: Equatable {
        let managedItemCount: Int
        let unresolvedSourcePIDCount: Int
        let presentBundleIDs: Set<String>

        var policyObservation: MenuBarStartupSettlingPolicy.PollObservation {
            MenuBarStartupSettlingPolicy.PollObservation(
                managedItemCount: managedItemCount,
                unresolvedSourcePIDCount: unresolvedSourcePIDCount,
                presentBundleIDs: presentBundleIDs
            )
        }
    }

    enum Outcome: Equatable {
        case completed
        case cancelled
    }

    struct Operations {
        let waitForInitialCache: () async -> Void
        let pollCache: () async -> Observation
        let finishSettlingWindow: () -> Void
        let runFastRestore: () async -> Void
        let runAuthoritativeRestore: () async -> Void
        let sleepBetweenPolls: () async throws -> Void
        let now: () -> ContinuousClock.Instant
    }

    struct Diagnostics {
        var recordWaitingForExpectedSet: (Set<String>) -> Void = { _ in }
        var recordDeadlineReached: (ContinuousClock.Instant) -> Void = { _ in }
        var recordSettled: (MenuBarStartupSettlingPolicy.SettledReason) -> Void = { _ in }
        var recordWait: (MenuBarStartupSettlingPolicy.WaitReason) -> Void = { _ in }
        var recordCancelled: () -> Void = {}
        var recordEnded: () -> Void = {}
        var recordFastRestoreStart: () -> Void = {}
    }

    @MainActor
    static func execute(
        configuration: MenuBarStartupSettlingPolicy.StartConfiguration,
        operations: Operations,
        diagnostics: Diagnostics = Diagnostics()
    ) async -> Outcome {
        await operations.waitForInitialCache()

        var pollState = MenuBarStartupSettlingPolicy.PollState.initial
        let waitingFor = configuration.expectedBundleIDs
        if !waitingFor.isEmpty {
            diagnostics.recordWaitingForExpectedSet(waitingFor)
        }

        settlingLoop: while !Task.isCancelled {
            if operations.now() > configuration.deadline {
                diagnostics.recordDeadlineReached(configuration.deadline)
                break settlingLoop
            }

            let observation = await operations.pollCache()
            let pollDecision = MenuBarStartupSettlingPolicy.evaluatePoll(
                observation: observation.policyObservation,
                waitingFor: waitingFor,
                state: pollState
            )

            switch pollDecision {
            case let .settled(settledReason):
                diagnostics.recordSettled(settledReason)
                break settlingLoop
            case let .wait(nextState, waitReason):
                pollState = nextState
                diagnostics.recordWait(waitReason)
            }

            do {
                try await operations.sleepBetweenPolls()
            } catch is CancellationError {
                diagnostics.recordCancelled()
                return .cancelled
            } catch {
                return .cancelled
            }
        }

        guard !Task.isCancelled else {
            return .cancelled
        }

        operations.finishSettlingWindow()
        diagnostics.recordEnded()
        diagnostics.recordFastRestoreStart()
        await operations.runFastRestore()
        await operations.runAuthoritativeRestore()
        return .completed
    }
}
