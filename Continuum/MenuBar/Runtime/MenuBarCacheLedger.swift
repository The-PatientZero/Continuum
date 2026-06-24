//
//  MenuBarCacheLedger.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Baseline metadata captured from successful cache observations.
///
/// The item cache stores rich menu-bar items. This ledger stores the small
/// comparison sets that make refresh decisions cheap and keep transient clone
/// windows or source-PID drift from corrupting later cache cycles.
struct MenuBarCacheLedger: Equatable {
    /// A list of the menu bar item window identifiers at the time of the
    /// previous cache.
    private(set) var cachedItemWindowIDs = [CGWindowID]()

    /// A mapping from window identifiers to resolved source process
    /// identifiers from the previous cache cycle.
    private(set) var cachedItemPIDs = [CGWindowID: pid_t]()

    /// Window identifiers of the system clone windows seen in the most recent
    /// cache cycle.
    private(set) var cachedCloneWindowIDs = Set<CGWindowID>()

    mutating func recordObservation(
        itemWindowIDs: [CGWindowID],
        cloneWindowIDs: Set<CGWindowID>
    ) {
        cachedItemWindowIDs = itemWindowIDs
        cachedCloneWindowIDs = cloneWindowIDs
    }

    mutating func recordResolvedSourcePIDs(_ pids: [CGWindowID: pid_t]) {
        cachedItemPIDs = pids
    }

    mutating func clear() {
        cachedItemWindowIDs.removeAll()
        cachedItemPIDs.removeAll()
        cachedCloneWindowIDs.removeAll()
    }
}
