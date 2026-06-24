//
//  MenuBarEventOperationGate.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Serializes synthetic menu-bar event operations and recovers leaked waits.
///
/// Menu-bar moves and clicks both post low-level CGEvents. Letting those
/// overlap can leave apps or WindowServer tracking state inconsistent, so this
/// gate provides one explicit runtime contract for acquisition, timeout, reset,
/// and release behavior.
actor MenuBarEventOperationGate {
    struct Permit: Equatable, Sendable {
        let recoveredFromTimeout: Bool
    }

    enum AcquireError: Error, Equatable {
        case timedOutAfterReset
    }

    static let defaultAcquireTimeout: Duration = .milliseconds(3_500)

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct TimeoutError: Error {}

    private let initialPermits: Int
    private var permits: Int
    private var waiters: [Waiter] = []

    init(permits: Int = 1) {
        precondition(permits >= 0, "MenuBarEventOperationGate requires a non-negative permit count")
        initialPermits = permits
        self.permits = permits
    }

    func acquire(timeout: Duration = MenuBarEventOperationGate.defaultAcquireTimeout) async throws -> Permit {
        do {
            try await wait(timeout: timeout)
            return Permit(recoveredFromTimeout: false)
        } catch is TimeoutError {
            reset(to: initialPermits)
            do {
                try await wait(timeout: timeout)
                return Permit(recoveredFromTimeout: true)
            } catch is TimeoutError {
                throw AcquireError.timedOutAfterReset
            }
        }
    }

    func release() {
        signal()
    }

    private func wait() async throws {
        if Task.isCancelled {
            throw CancellationError()
        }

        permits -= 1
        if permits >= 0 {
            return
        }

        let id = UUID()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: { [weak self] in
            Task.detached { await self?.cancelWaiter(withID: id) }
        }
    }

    private func wait(timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.wait()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TimeoutError()
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func cancelWaiter(withID id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        permits += 1
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func signal() {
        permits += 1
        if permits <= 0, let waiter = waiters.first {
            waiters.removeFirst()
            waiter.continuation.resume(returning: ())
        }
    }

    private func reset(to permits: Int) {
        for waiter in waiters {
            waiter.continuation.resume(throwing: CancellationError())
        }
        waiters.removeAll()
        self.permits = permits
    }
}
