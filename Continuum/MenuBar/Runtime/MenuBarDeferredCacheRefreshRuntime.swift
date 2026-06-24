//
//  MenuBarDeferredCacheRefreshRuntime.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Owns the live task handle for a delayed post-mutation cache refresh.
///
/// Saved-layout apply can exit through several transient WindowServer states.
/// Coalescing those exits into one pending refresh prevents restore churn from
/// queueing duplicate cache cycles while still allowing the cache gate to do
/// the expensive serialization work.
struct MenuBarDeferredCacheRefreshRuntime {
    struct Token: Equatable {
        fileprivate let rawValue: UInt64
    }

    enum ScheduleDecision: Equatable {
        case schedule(Token)
        case alreadyScheduled
    }

    private var task: Task<Void, Never>?
    private var activeToken: Token?
    private var nextTokenRawValue: UInt64 = 0

    var hasPendingRefresh: Bool {
        activeToken != nil
    }

    mutating func schedule() -> ScheduleDecision {
        guard activeToken == nil else {
            return .alreadyScheduled
        }

        nextTokenRawValue &+= 1
        let token = Token(rawValue: nextTokenRawValue)
        activeToken = token
        return .schedule(token)
    }

    mutating func attachTask(_ task: Task<Void, Never>, for token: Token) {
        guard activeToken == token else {
            task.cancel()
            return
        }

        self.task = task
    }

    mutating func finish(_ token: Token) {
        guard activeToken == token else {
            return
        }

        task = nil
        activeToken = nil
    }

    mutating func cancel() {
        task?.cancel()
        task = nil
        activeToken = nil
    }
}
