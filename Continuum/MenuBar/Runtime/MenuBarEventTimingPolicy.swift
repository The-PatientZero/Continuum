//
//  MenuBarEventTimingPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Adaptive timing policy for synthetic menu-bar events.
///
/// The manager owns measured per-item caches; this policy owns the default
/// values and update clamps so move/click retry behavior stays stable.
enum MenuBarEventTimingPolicy {
    static let defaultMoveTimeout: Duration = .milliseconds(250)
    static let bentoBoxMoveTimeout: Duration = .milliseconds(300)
    static let moveTimeoutRange: ClosedRange<Duration> = .milliseconds(250) ... .milliseconds(500)

    static let defaultClickTimeout: Duration = .milliseconds(350)
    static let slowClickTimeout: Duration = .milliseconds(500)
    static let clickTimeoutRange: ClosedRange<Duration> = .milliseconds(200) ... .milliseconds(1_000)

    private static let slowClickBundleIdentifiers = [
        "com.bitsplash.PasteNow",
        "com.charliemonroe.Downie-setapp",
        "com.if.Amphetamine",
        "com.hegenberg.BetterTouchTool",
        "net.matthewpalmer.Vanilla",
    ]

    static func defaultMoveTimeout(for item: MenuBarItem) -> Duration {
        item.isBentoBox ? bentoBoxMoveTimeout : defaultMoveTimeout
    }

    static func updatedMoveTimeout(
        previous: Duration,
        measured: Duration
    ) -> Duration {
        ((previous + measured) / 2).clamped(to: moveTimeoutRange)
    }

    static func defaultClickTimeout(for item: MenuBarItem) -> Duration {
        let namespace = item.tag.namespace.description
        if slowClickBundleIdentifiers.contains(where: { namespace.contains($0) }) {
            return slowClickTimeout
        }
        return defaultClickTimeout
    }

    static func updatedClickTimeout(
        previous: Duration,
        measured: Duration
    ) -> Duration {
        ((previous + measured) / 2).clamped(to: clickTimeoutRange)
    }
}
