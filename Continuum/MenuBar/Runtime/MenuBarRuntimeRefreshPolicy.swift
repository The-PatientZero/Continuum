//
//  MenuBarRuntimeRefreshPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation

/// Cadence for the lightweight runtime refresh loop.
///
/// The manager owns subscriptions and tasks; this policy owns the timing
/// contract so startup, app churn, and polling stay cheap and testable.
enum MenuBarRuntimeRefreshPolicy {
    static let initialCacheMaxAttempts = 10
    static let initialCacheRetryDelay: Duration = .milliseconds(100)

    static var appLaunchDebounce: DispatchQueue.SchedulerTimeType.Stride {
        .seconds(1)
    }

    static var appTerminationDebounce: DispatchQueue.SchedulerTimeType.Stride {
        .seconds(1)
    }

    static var appActivationDebounce: DispatchQueue.SchedulerTimeType.Stride {
        .milliseconds(500)
    }

    static let trackedAppLaunchSettlingDuration: Duration = .seconds(8)
    static let appLaunchFollowUpDelays: [Duration] = [
        .milliseconds(2_500),
        .milliseconds(2_500),
    ]

    static let cacheTickIntervalSeconds: TimeInterval = 3

    static var initialCacheAttempts: ClosedRange<Int> {
        1 ... initialCacheMaxAttempts
    }

    static func shouldRetryInitialCache(after attempt: Int) -> Bool {
        attempt < initialCacheMaxAttempts
    }
}
