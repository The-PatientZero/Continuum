//
//  MenuBarClickExecution.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Runtime state for one synthetic menu bar click execution.
///
/// The manager owns CGEvent posting; this type owns the retry budget so normal
/// activation clicks and temporary-reveal fallback clicks share the same bounded
/// attempt contract.
struct MenuBarClickExecution {
    enum AttemptContinuation: Equatable {
        case retry
        case stop
    }

    let maxAttempts: Int
    private(set) var currentAttempt = 0

    var canStartAttempt: Bool {
        currentAttempt < maxAttempts
    }

    init(maxAttempts: Int) {
        self.maxAttempts = max(1, maxAttempts)
    }

    mutating func beginAttempt() -> Int? {
        guard canStartAttempt else {
            return nil
        }
        currentAttempt += 1
        return currentAttempt
    }

    func continuationAfterFailedAttempt() -> AttemptContinuation {
        currentAttempt < maxAttempts ? .retry : .stop
    }
}
