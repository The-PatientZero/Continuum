//
//  MenuBarObservationRetryPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Retry policy for transient zero-item WindowServer observations.
///
/// A zero-item read can happen during display reconfiguration or brief
/// WindowServer stalls. Retry once, then preserve the known-good cache and
/// degrade diagnostics rather than replacing the UI with an empty model.
enum MenuBarObservationRetryPolicy {
    static let retryDelay: Duration = .milliseconds(250)
    static let defaultMaxAttempts = 2
    static let exhaustedDetail = "getMenuBarItems returned zero items after retry"

    enum Decision: Equatable {
        case accept
        case retry(after: Duration)
        case fail(detail: String)
    }

    static func evaluate(
        observedItemCount: Int,
        attempt: Int,
        maxAttempts: Int = defaultMaxAttempts
    ) -> Decision {
        guard observedItemCount == 0 else {
            return .accept
        }

        let normalizedAttempt = max(1, attempt)
        let normalizedMaxAttempts = max(1, maxAttempts)
        guard normalizedAttempt < normalizedMaxAttempts else {
            return .fail(detail: exhaustedDetail)
        }

        return .retry(after: retryDelay)
    }
}
