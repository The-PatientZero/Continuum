//
//  MenuBarSavedSectionOrderLedger.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Runtime ledger for persisted per-section menu bar item order.
///
/// The order is stored right-to-left, matching the manager's cache arrays.
/// Keeping it behind a ledger makes save/prune/reset transitions explicit
/// instead of letting the manager mutate a loose dictionary.
struct MenuBarSavedSectionOrderLedger: Equatable {
    static let defaultsKey = "MenuBarItemManager.savedSectionOrder"

    private(set) var order = [String: [String]]()

    var isEmpty: Bool {
        order.isEmpty
    }

    var entryCounts: [Int] {
        order.values.map(\.count)
    }

    var persistenceSnapshot: [String: [String]] {
        order
    }

    mutating func load(_ storedOrder: [String: [String]]) {
        order = storedOrder
    }

    mutating func replace(with newOrder: [String: [String]]) {
        order = newOrder
    }

    @discardableResult
    mutating func replaceIfChanged(with newOrder: [String: [String]]) -> Bool {
        guard newOrder != order else {
            return false
        }
        order = newOrder
        return true
    }

    mutating func clear() {
        order.removeAll()
    }
}
