//
//  MenuBarMoveExecution.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Runtime state for one menu bar move command execution.
///
/// The live manager still owns CGEvent posting, but this type owns the retry
/// contract: which attempt is active, whether the event path visibly moved the
/// item, and how that state is reported to diagnostics.
struct MenuBarMoveExecution {
    enum PositionMatchDecision: Equatable {
        case accept
        case retryAsPossibleFalsePositive
    }

    enum AttemptContinuation: Equatable {
        case retry
        case stop
    }

    let command: MenuBarMoveCommand
    private(set) var currentAttempt = 0
    private(set) var observedDisplacement = false

    var maxAttempts: Int {
        command.normalizedMaxAttempts
    }

    var canStartAttempt: Bool {
        currentAttempt < maxAttempts
    }

    init(command: MenuBarMoveCommand) {
        self.command = command
    }

    mutating func beginAttempt() -> Int? {
        guard canStartAttempt else {
            return nil
        }
        currentAttempt += 1
        return currentAttempt
    }

    mutating func recordObservedDisplacement() {
        observedDisplacement = true
    }

    func acceptsCurrentPositionMatch() -> Bool {
        guard currentAttempt > 0 else {
            return false
        }
        return command.acceptsPositionMatch(
            atAttempt: currentAttempt,
            observedDisplacement: observedDisplacement
        )
    }

    func positionMatchDecision() -> PositionMatchDecision {
        acceptsCurrentPositionMatch() ? .accept : .retryAsPossibleFalsePositive
    }

    func shouldRetryCurrentAttempt() -> Bool {
        guard currentAttempt > 0 else {
            return false
        }
        return command.shouldRetry(afterAttempt: currentAttempt)
    }

    func continuationAfterUnverifiedAttempt() -> AttemptContinuation {
        shouldRetryCurrentAttempt() ? .retry : .stop
    }

    func continuationAfterFailedAttempt() -> AttemptContinuation {
        shouldRetryCurrentAttempt() ? .retry : .stop
    }

    func failedAttemptDetail(error: Error) -> String {
        """
        Move failed: \(command.diagnosticDescription), \
        attempt=\(currentAttempt)/\(maxAttempts), \
        displaced=\(observedDisplacement), error=\(error)
        """
    }

    func exhaustedAttemptsDetail() -> String {
        """
        Move exhausted \(maxAttempts) attempt(s): \
        \(command.diagnosticDescription), displaced=\(observedDisplacement)
        """
    }
}
