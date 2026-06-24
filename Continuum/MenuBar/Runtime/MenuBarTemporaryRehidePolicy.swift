//
//  MenuBarTemporaryRehidePolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Pure control-plane policy for rehiding temporarily revealed items.
///
/// The manager owns observation, movement, timers, and persistence. This policy
/// owns the decisions about whether to start now, reschedule, keep retrying in
/// memory, or hand off to pending relocation recovery.
enum MenuBarTemporaryRehidePolicy {
    static let interfaceShowingRetryInterval: TimeInterval = 3
    static let userInputRetryInterval: TimeInterval = 1
    static let observationMissRetryInterval: TimeInterval = 3
    static let failedContextsRetryInterval: TimeInterval = 3

    enum StartDecision: Equatable {
        case proceed
        case reschedule(reason: StartDeferralReason, after: TimeInterval)
    }

    enum StartDeferralReason: Equatable {
        case interfaceShowing
        case recentUserInput
    }

    enum MissingItemAction: Equatable {
        case keepInMemory
        case giveUpToPendingRelocation
    }

    enum MoveFailureAction: Equatable {
        case retryImmediately
        case retryLater
        case waitForRelaunch(pendingRelocationValue: String)
    }

    static func startDecision(
        force: Bool,
        interfaceIsShowing: Bool,
        userInputPaused: Bool
    ) -> StartDecision {
        if force {
            return .proceed
        }
        if interfaceIsShowing {
            return .reschedule(
                reason: .interfaceShowing,
                after: interfaceShowingRetryInterval
            )
        }
        if !userInputPaused {
            return .reschedule(
                reason: .recentUserInput,
                after: userInputRetryInterval
            )
        }
        return .proceed
    }

    static func observationMissRetryDelay(force: Bool) -> TimeInterval? {
        force ? nil : observationMissRetryInterval
    }

    static func failedContextsRetryDelay(force: Bool) -> TimeInterval? {
        force ? nil : failedContextsRetryInterval
    }

    static func missingItemAction(afterNotFoundAttempts attempts: Int) -> MissingItemAction {
        switch PendingLedger.notFoundDecision(after: attempts) {
        case .retryLater:
            .keepInMemory
        case .giveUpToPendingRelocation:
            .giveUpToPendingRelocation
        }
    }

    static func moveFailureAction(
        afterRehideAttempts attempts: Int,
        windowID: CGWindowID,
        originalSection: MenuBarSection.Name
    ) -> MoveFailureAction {
        switch PendingLedger.rehideFailureDecision(after: attempts) {
        case .retryImmediately:
            .retryImmediately
        case .retryLater:
            .retryLater
        case .waitForRelaunch:
            .waitForRelaunch(
                pendingRelocationValue: PendingLedger.makeWaitForRelaunchValue(
                    windowID: windowID,
                    section: originalSection
                )
            )
        }
    }
}
