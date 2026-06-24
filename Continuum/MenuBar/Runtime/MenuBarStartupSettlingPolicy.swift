//
//  MenuBarStartupSettlingPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Pure policy for startup/app-restart settling windows.
///
/// Settling protects the runtime from restoring or persisting layout while
/// macOS is still attaching NSStatusItems, resolving source PIDs, or moving
/// the active menu bar between displays. The manager owns tasks and cache
/// calls; this policy owns authority, deadline, and poll decisions.
enum MenuBarStartupSettlingPolicy {
    static let performSetupReason = "performSetup"
    static let stablePollTarget = 3
    static let allowedUnresolvedSourcePIDCount = 1

    enum Kind: Equatable, CustomStringConvertible {
        case cold
        case transient
        case expectedSet

        var description: String {
            switch self {
            case .cold:
                "cold"
            case .transient:
                "transient"
            case .expectedSet:
                "expectedSet"
            }
        }
    }

    struct StartConfiguration: Equatable {
        let kind: Kind
        let expectedBundleIDs: Set<String>
        let deadline: ContinuousClock.Instant
    }

    enum StartDecision: Equatable {
        case start(StartConfiguration)
        case ignore(mergedExpectedBundleIDs: Set<String>)
    }

    struct PollState: Equatable {
        var lastSeenCount: Int
        var stablePolls: Int

        static let initial = PollState(lastSeenCount: -1, stablePolls: 0)
    }

    struct PollObservation: Equatable {
        let managedItemCount: Int
        let unresolvedSourcePIDCount: Int
        let presentBundleIDs: Set<String>
    }

    enum SettledReason: Equatable {
        case expectedBundleIDsReattached(count: Int)
        case countStable(count: Int, stablePolls: Int, unresolvedSourcePIDCount: Int)
    }

    enum WaitReason: Equatable {
        case missingExpectedBundleIDs(Set<String>)
        case sourcePIDsUnresolved(managedItemCount: Int, unresolvedSourcePIDCount: Int)
        case countChanged(previous: Int, current: Int, unresolvedSourcePIDCount: Int)
        case waitingForStableCount(count: Int, stablePolls: Int, target: Int, unresolvedSourcePIDCount: Int)
    }

    enum PollDecision: Equatable {
        case settled(SettledReason)
        case wait(nextState: PollState, reason: WaitReason)
    }

    static func planStart(
        reason: String,
        existingKind: Kind?,
        existingExpectedBundleIDs: Set<String>,
        existingDeadline: ContinuousClock.Instant?,
        incomingExpectedBundleIDs: Set<String>,
        now: ContinuousClock.Instant = .now,
        maxDuration: Duration
    ) -> StartDecision {
        let mergedExpectedBundleIDs = existingExpectedBundleIDs.union(incomingExpectedBundleIDs)
        let incomingKind = kind(reason: reason, expectedBundleIDs: incomingExpectedBundleIDs)

        if let existingKind,
           incomingKind == .transient,
           existingKind == .cold || existingKind == .expectedSet
        {
            return .ignore(mergedExpectedBundleIDs: mergedExpectedBundleIDs)
        }

        let newDeadline = now.advanced(by: maxDuration)
        let deadline = max(existingDeadline ?? newDeadline, newDeadline)
        return .start(
            StartConfiguration(
                kind: incomingKind,
                expectedBundleIDs: mergedExpectedBundleIDs,
                deadline: deadline
            )
        )
    }

    static func evaluatePoll(
        observation: PollObservation,
        waitingFor expectedBundleIDs: Set<String>,
        state: PollState,
        stableTarget: Int = stablePollTarget
    ) -> PollDecision {
        let sourcePIDsOK = observation.managedItemCount > 0 &&
            observation.unresolvedSourcePIDCount <= allowedUnresolvedSourcePIDCount

        if !expectedBundleIDs.isEmpty {
            let missingBundleIDs = expectedBundleIDs.subtracting(observation.presentBundleIDs)
            guard missingBundleIDs.isEmpty else {
                return .wait(nextState: state, reason: .missingExpectedBundleIDs(missingBundleIDs))
            }
            guard sourcePIDsOK else {
                return .wait(
                    nextState: state,
                    reason: .sourcePIDsUnresolved(
                        managedItemCount: observation.managedItemCount,
                        unresolvedSourcePIDCount: observation.unresolvedSourcePIDCount
                    )
                )
            }
            return .settled(.expectedBundleIDsReattached(count: expectedBundleIDs.count))
        }

        if sourcePIDsOK, observation.managedItemCount == state.lastSeenCount {
            let nextStablePolls = state.stablePolls + 1
            let nextState = PollState(
                lastSeenCount: state.lastSeenCount,
                stablePolls: nextStablePolls
            )
            if nextStablePolls >= stableTarget {
                return .settled(
                    .countStable(
                        count: observation.managedItemCount,
                        stablePolls: nextStablePolls,
                        unresolvedSourcePIDCount: observation.unresolvedSourcePIDCount
                    )
                )
            }
            return .wait(
                nextState: nextState,
                reason: .waitingForStableCount(
                    count: observation.managedItemCount,
                    stablePolls: nextStablePolls,
                    target: stableTarget,
                    unresolvedSourcePIDCount: observation.unresolvedSourcePIDCount
                )
            )
        }

        let nextState = PollState(
            lastSeenCount: observation.managedItemCount,
            stablePolls: 0
        )
        if observation.managedItemCount != state.lastSeenCount {
            return .wait(
                nextState: nextState,
                reason: .countChanged(
                    previous: state.lastSeenCount,
                    current: observation.managedItemCount,
                    unresolvedSourcePIDCount: observation.unresolvedSourcePIDCount
                )
            )
        }

        return .wait(
            nextState: nextState,
            reason: .sourcePIDsUnresolved(
                managedItemCount: observation.managedItemCount,
                unresolvedSourcePIDCount: observation.unresolvedSourcePIDCount
            )
        )
    }

    private static func kind(reason: String, expectedBundleIDs: Set<String>) -> Kind {
        if !expectedBundleIDs.isEmpty {
            return .expectedSet
        }
        if reason == performSetupReason {
            return .cold
        }
        return .transient
    }
}
