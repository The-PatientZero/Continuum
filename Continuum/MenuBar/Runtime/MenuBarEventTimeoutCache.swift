//
//  MenuBarEventTimeoutCache.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Mutable runtime history for adaptive synthetic event timeouts.
///
/// `MenuBarEventTimingPolicy` owns defaults and clamp math. This cache owns
/// the per-item measured history so move/click event execution does not keep
/// independent dictionaries in the manager.
struct MenuBarEventTimeoutCache: Equatable {
    private var moveTimeouts = [MenuBarItemTag: Duration]()
    private var clickTimeouts = [MenuBarItemTag: Duration]()

    func moveTimeout(for item: MenuBarItem) -> Duration {
        moveTimeouts[item.tag] ?? MenuBarEventTimingPolicy.defaultMoveTimeout(for: item)
    }

    mutating func updateMoveTimeout(_ measured: Duration, for item: MenuBarItem) {
        let current = moveTimeout(for: item)
        moveTimeouts[item.tag] = MenuBarEventTimingPolicy.updatedMoveTimeout(
            previous: current,
            measured: measured
        )
    }

    mutating func pruneMoveTimeouts(keeping validTags: Set<MenuBarItemTag>) {
        moveTimeouts = moveTimeouts.filter { validTags.contains($0.key) }
    }

    func clickTimeout(for item: MenuBarItem) -> Duration {
        clickTimeouts[item.tag] ?? MenuBarEventTimingPolicy.defaultClickTimeout(for: item)
    }

    @discardableResult
    mutating func updateClickTimeout(_ measured: Duration, for item: MenuBarItem) -> Duration {
        let current = clickTimeout(for: item)
        let updated = MenuBarEventTimingPolicy.updatedClickTimeout(
            previous: current,
            measured: measured
        )
        clickTimeouts[item.tag] = updated
        return updated
    }

    mutating func pruneClickTimeouts(keeping validTags: Set<MenuBarItemTag>) {
        clickTimeouts = clickTimeouts.filter { validTags.contains($0.key) }
    }
}
