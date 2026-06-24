//
//  MenuBarEventRefreshRuntime.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Coalesces app/timer-triggered cache refresh requests into one serial lane.
///
/// NSWorkspace notifications and the lightweight timer can arrive while a cache
/// cycle is still observing or moving items. Keeping one active task plus one
/// merged pending request avoids task stampedes and prevents a refresh from
/// being dropped just because the cache operation gate was busy.
struct MenuBarEventRefreshRuntime {
    struct Token: Equatable {
        fileprivate let rawValue: UInt64
    }

    struct Request: Equatable {
        var requiresFullRefresh: Bool
        var followUpDelays: [Duration]

        static let ifNeeded = Request(
            requiresFullRefresh: false,
            followUpDelays: []
        )

        static func fullRefresh(followUpDelays: [Duration] = []) -> Request {
            Request(
                requiresFullRefresh: true,
                followUpDelays: followUpDelays
            )
        }

        func merged(with other: Request) -> Request {
            Request(
                requiresFullRefresh: requiresFullRefresh || other.requiresFullRefresh,
                followUpDelays: followUpDelays.count >= other.followUpDelays.count
                    ? followUpDelays
                    : other.followUpDelays
            )
        }
    }

    enum ScheduleDecision: Equatable {
        case start(Token, Request)
        case coalesced(Request)
    }

    enum FinishDecision: Equatable {
        case idle
        case startNext(Token, Request)
    }

    private var task: Task<Void, Never>?
    private var activeToken: Token?
    private var pendingRequest: Request?
    private var nextTokenRawValue: UInt64 = 0

    var hasActiveRefresh: Bool {
        activeToken != nil
    }

    var hasPendingRefresh: Bool {
        pendingRequest != nil
    }

    mutating func schedule(_ request: Request) -> ScheduleDecision {
        guard activeToken != nil else {
            let token = makeToken()
            activeToken = token
            return .start(token, request)
        }

        let mergedRequest = pendingRequest.map { $0.merged(with: request) } ?? request
        pendingRequest = mergedRequest
        return .coalesced(mergedRequest)
    }

    mutating func attachTask(_ task: Task<Void, Never>, for token: Token) {
        guard activeToken == token else {
            task.cancel()
            return
        }

        self.task = task
    }

    mutating func finish(_ token: Token) -> FinishDecision {
        guard activeToken == token else {
            return .idle
        }

        task = nil

        guard let nextRequest = pendingRequest else {
            activeToken = nil
            return .idle
        }

        pendingRequest = nil
        let token = makeToken()
        activeToken = token
        return .startNext(token, nextRequest)
    }

    mutating func cancel() {
        task?.cancel()
        task = nil
        activeToken = nil
        pendingRequest = nil
    }

    private mutating func makeToken() -> Token {
        nextTokenRawValue &+= 1
        return Token(rawValue: nextTokenRawValue)
    }
}
