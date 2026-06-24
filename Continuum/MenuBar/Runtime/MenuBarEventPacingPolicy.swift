//
//  MenuBarEventPacingPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Pacing constants for synthetic menu-bar event operations.
///
/// Timeouts live in ``MenuBarEventTimingPolicy``; this policy owns the shorter
/// inter-event delays and polling cadences that keep WindowServer state stable
/// without making temporary reveal and click flows feel heavy.
enum MenuBarEventPacingPolicy {
    static let inputPauseQuietWindow: Duration = .milliseconds(50)
    static let inputPausePollInterval: Duration = .milliseconds(50)
    static let moveOperationMinimumSpacing: Duration = .milliseconds(25)
    static let defaultEventSleep: Duration = .milliseconds(25)
    static let moveResponsePollInterval: Duration = .milliseconds(10)
    static let moveWarpSettleDelay: Duration = .milliseconds(20)
    static let moveFallbackMouseUpTimeout: Duration = .milliseconds(100)
    static let clickWarpSettleDelay: Duration = .milliseconds(10)
    static let itemPositionSettleTimeout: Duration = .milliseconds(250)
    static let itemPositionSettlePollInterval: Duration = .milliseconds(20)
    static let revealedItemFastSettleTimeout: Duration = .milliseconds(150)
    static let revealedItemFastSettlePollInterval: Duration = .milliseconds(15)
    static let revealedItemPostMoveProcessingDelay: Duration = .milliseconds(25)
    static let popupCaptureDelay: Duration = .milliseconds(100)
    static let rehideUserInputQuietWindow: Duration = .milliseconds(250)
    static let rehideSettleFromTemporaryShow: Duration = .milliseconds(50)
    static let rehideSettleDefault: Duration = .milliseconds(250)

    static func moveOperationBuffer(elapsedSinceLastMove elapsed: Duration) -> Duration {
        max(moveOperationMinimumSpacing - elapsed, .zero)
    }

    static func rehideSettleDelay(isCalledFromTemporarilyShow: Bool) -> Duration {
        isCalledFromTemporarilyShow ? rehideSettleFromTemporaryShow : rehideSettleDefault
    }
}
