//
//  MenuBarCacheCycleRuntime.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Serializes cache operations to prevent races between concurrent cache cycles.
///
/// When a relocation move is in flight, a concurrent cache call can snapshot
/// positions before the move completes and cache items in the wrong section.
actor MenuBarCacheOperationGate {
    private var isInProgress = false

    func begin() -> Bool {
        guard !isInProgress else { return false }
        isInProgress = true
        return true
    }

    func end() {
        isInProgress = false
    }
}

/// Mutable runtime state for one cache-cycle lane.
///
/// The manager owns observation and cache mutation. This runtime owns the
/// lightweight lifecycle state shared by cache admission, invalidation, and
/// deferred follow-up recaches.
struct MenuBarCacheCycleRuntime {
    struct FollowUpToken: Equatable {
        fileprivate let rawValue: UInt64
    }

    enum FollowUpScheduleDecision: Equatable {
        case start(FollowUpToken)
        case waitForRunningFollowUp
    }

    enum FollowUpFinishDecision: Equatable {
        case idle
        case startNext(FollowUpToken)
    }

    let operationGate = MenuBarCacheOperationGate()

    private var ledger = MenuBarCacheLedger()
    private var backgroundContinuation: CheckedContinuation<Void, Never>?
    private var followUpTask: Task<Void, Never>?
    private var followUpToken: FollowUpToken?
    private var followUpIsRunning = false
    private var followUpRequestedAfterCurrentRun = false
    private var followUpContinuations = [CheckedContinuation<Void, Never>]()
    private var nextFollowUpTokenRawValue: UInt64 = 0

    var cachedItemWindowIDs: [CGWindowID] {
        ledger.cachedItemWindowIDs
    }

    var cachedItemPIDs: [CGWindowID: pid_t] {
        ledger.cachedItemPIDs
    }

    var cachedCloneWindowIDs: Set<CGWindowID> {
        ledger.cachedCloneWindowIDs
    }

    var hasPendingBackgroundContinuation: Bool {
        backgroundContinuation != nil
    }

    var hasScheduledFollowUpRecache: Bool {
        followUpToken != nil
    }

    var hasPendingFollowUpContinuation: Bool {
        !followUpContinuations.isEmpty
    }

    mutating func recordObservation(
        itemWindowIDs: [CGWindowID],
        cloneWindowIDs: Set<CGWindowID>
    ) {
        ledger.recordObservation(
            itemWindowIDs: itemWindowIDs,
            cloneWindowIDs: cloneWindowIDs
        )
    }

    mutating func recordResolvedSourcePIDs(_ pids: [CGWindowID: pid_t]) {
        ledger.recordResolvedSourcePIDs(pids)
    }

    mutating func clearLedger() {
        ledger.clear()
    }

    mutating func storeBackgroundContinuation(
        _ continuation: CheckedContinuation<Void, Never>
    ) {
        backgroundContinuation = continuation
    }

    mutating func takeBackgroundContinuation() -> CheckedContinuation<Void, Never>? {
        let continuation = backgroundContinuation
        backgroundContinuation = nil
        return continuation
    }

    mutating func resumeBackgroundContinuation() {
        takeBackgroundContinuation()?.resume()
    }

    mutating func scheduleFollowUpRecache() -> FollowUpScheduleDecision {
        moveBackgroundContinuationToFollowUp()

        if followUpIsRunning {
            followUpRequestedAfterCurrentRun = true
            return .waitForRunningFollowUp
        }

        followUpTask?.cancel()
        followUpTask = nil

        let token = makeFollowUpToken()
        followUpToken = token
        followUpRequestedAfterCurrentRun = false
        return .start(token)
    }

    mutating func attachFollowUpTask(_ task: Task<Void, Never>, for token: FollowUpToken) {
        guard followUpToken == token else {
            task.cancel()
            return
        }

        followUpTask = task
    }

    mutating func beginFollowUpRecache(_ token: FollowUpToken) -> Bool {
        guard followUpToken == token else {
            return false
        }

        followUpTask = nil
        followUpIsRunning = true
        return true
    }

    mutating func finishFollowUpRecache(_ token: FollowUpToken) -> FollowUpFinishDecision {
        guard followUpToken == token else {
            return .idle
        }

        followUpTask = nil
        followUpIsRunning = false

        if followUpRequestedAfterCurrentRun {
            followUpRequestedAfterCurrentRun = false
            let nextToken = makeFollowUpToken()
            followUpToken = nextToken
            return .startNext(nextToken)
        }

        followUpToken = nil
        resumeFollowUpContinuations()
        return .idle
    }

    mutating func cancelFollowUpRecache() {
        followUpTask?.cancel()
        followUpTask = nil
        followUpToken = nil
        followUpIsRunning = false
        followUpRequestedAfterCurrentRun = false
        resumeFollowUpContinuations()
    }

    private mutating func moveBackgroundContinuationToFollowUp() {
        if let continuation = takeBackgroundContinuation() {
            followUpContinuations.append(continuation)
        }
    }

    private mutating func resumeFollowUpContinuations() {
        let continuations = followUpContinuations
        followUpContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private mutating func makeFollowUpToken() -> FollowUpToken {
        nextFollowUpTokenRawValue &+= 1
        return FollowUpToken(rawValue: nextFollowUpTokenRawValue)
    }
}
