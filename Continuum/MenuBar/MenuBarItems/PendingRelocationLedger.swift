//
//  PendingRelocationLedger.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Mutable storage boundary for pending temporary-reveal relocations.
///
/// PendingLedger is the pure planner. This ledger owns the paired persisted
/// maps that keep a temporarily shown item returnable after move failure,
/// app quit, or app relaunch.
struct PendingRelocationLedger: Equatable {
    static let relocationsDefaultsKey = "MenuBarItemManager.pendingRelocations"
    static let returnDestinationsDefaultsKey = "MenuBarItemManager.pendingReturnDestinations"

    private(set) var relocations = [String: String]()
    private(set) var returnDestinations = [String: [String: String]]()

    var isEmpty: Bool {
        relocations.isEmpty
    }

    var tagIdentifiers: [String] {
        Array(relocations.keys)
    }

    mutating func load(
        relocations: [String: String],
        returnDestinations: [String: [String: String]]
    ) {
        self.relocations = relocations
        self.returnDestinations = returnDestinations
    }

    mutating func record(
        _ metadata: MenuBarTemporaryRevealPolicy.PendingMetadata,
        for tagIdentifier: String
    ) {
        relocations[tagIdentifier] = metadata.relocationValue
        returnDestinations[tagIdentifier] = metadata.returnDestinationStorageValue
    }

    mutating func markWaitForRelaunch(_ value: String, for tagIdentifier: String) {
        relocations[tagIdentifier] = value
    }

    mutating func promoteWaitForRelaunch(
        for tagIdentifier: String,
        to section: MenuBarSection.Name
    ) {
        relocations[tagIdentifier] = PendingLedger.sectionKey(for: section)
    }

    @discardableResult
    mutating func clear(tagIdentifier: String) -> Bool {
        let removedRelocation = relocations.removeValue(forKey: tagIdentifier) != nil
        let removedReturnDestination = returnDestinations.removeValue(forKey: tagIdentifier) != nil
        return removedRelocation || removedReturnDestination
    }

    mutating func clearAll() {
        relocations.removeAll()
        returnDestinations.removeAll()
    }

    func rawRelocationValue(for tagIdentifier: String) -> String? {
        relocations[tagIdentifier]
    }

    func pendingEntry(for tagIdentifier: String) -> PendingLedger.PendingEntry? {
        guard let rawValue = rawRelocationValue(for: tagIdentifier) else {
            return nil
        }

        return PendingLedger.parsePendingEntry(
            tagIdentifier: tagIdentifier,
            rawValue: rawValue
        )
    }

    func relocationPlanningInput(
        contexts: [PendingLedger.RehideContextObservation]
    ) -> PendingLedger.RelocationPlanningInput {
        PendingLedger.relocationPlanningInput(
            contexts: contexts,
            pendingReturnDestinations: returnDestinations
        )
    }
}
