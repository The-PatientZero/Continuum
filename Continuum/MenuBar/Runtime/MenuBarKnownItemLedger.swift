//
//  MenuBarKnownItemLedger.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Runtime ledger for items Continuum has already observed with stable identity.
///
/// The ledger keeps the persisted identifier set and the one-shot suppression
/// flag that prevents first-run/reset/startup observations from being treated
/// as user-added menu bar items.
struct MenuBarKnownItemLedger: Equatable {
    static let defaultsKey = "MenuBarItemManager.knownItemIdentifiers"

    private(set) var identifiers = Set<String>()
    private(set) var suppressesNextNewLeftmostItemRelocation = false

    var count: Int {
        identifiers.count
    }

    var persistenceSnapshot: [String] {
        identifiers.sorted()
    }

    mutating func load(_ storedIdentifiers: [String]) {
        identifiers = Set(storedIdentifiers)
    }

    mutating func armFirstLaunchSuppressionIfEmpty() {
        suppressesNextNewLeftmostItemRelocation = identifiers.isEmpty
    }

    mutating func armNextNewLeftmostItemRelocationSuppression() {
        suppressesNextNewLeftmostItemRelocation = true
    }

    mutating func clearNextNewLeftmostItemRelocationSuppression() {
        suppressesNextNewLeftmostItemRelocation = false
    }

    mutating func clearIdentifiers() {
        identifiers.removeAll()
    }

    @discardableResult
    mutating func remember(_ newIdentifiers: Set<String>) -> Bool {
        let previousCount = identifiers.count
        identifiers.formUnion(newIdentifiers)
        return identifiers.count != previousCount
    }

    @discardableResult
    mutating func remember(_ identifier: String) -> Bool {
        identifiers.insert(identifier).inserted
    }

    @discardableResult
    mutating func seedPersistableIdentifiers(from items: [MenuBarItem]) -> Bool {
        remember(MenuBarKnownItemIdentifierPolicy.persistableBaseIdentifiers(from: items))
    }

    mutating func consumeRelocationSuppressionAndSeed(from items: [MenuBarItem]) -> Bool {
        guard suppressesNextNewLeftmostItemRelocation else {
            return false
        }
        seedPersistableIdentifiers(from: items)
        suppressesNextNewLeftmostItemRelocation = false
        return true
    }

    /// Returns whether `bundleID` owns a menu bar item Continuum already tracks.
    ///
    /// Identifiers are formatted as `namespace:title`. The trailing colon
    /// anchors the namespace match so one bundle ID cannot be a loose prefix of
    /// another (`org.x.fdm6` must not match `org.x.fdm6x:Item-0`).
    func tracksMenuBarItem(bundleID: String) -> Bool {
        identifiers.contains { $0.hasPrefix(bundleID + ":") }
    }
}
