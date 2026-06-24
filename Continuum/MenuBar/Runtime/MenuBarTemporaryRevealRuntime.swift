//
//  MenuBarTemporaryRevealRuntime.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@preconcurrency import Combine
import Foundation

/// Mutable runtime state for temporary reveal and smart rehide.
///
/// Policies decide whether to reveal, rehide, retry, or hand off to pending
/// recovery. This runtime object owns the live contexts and rehide trigger
/// handles so the manager does not coordinate that lifecycle with loose fields.
struct MenuBarTemporaryRevealRuntime {
    private(set) var contexts = [MenuBarTemporaryRevealContext]()
    private var rehideTimer: Timer?
    private var frontmostApplicationCancellable: AnyCancellable?

    var isEmpty: Bool {
        contexts.isEmpty
    }

    var interfaceIsShowing: Bool {
        contexts.contains(where: \.isShowingInterface)
    }

    var hasScheduledRehideTrigger: Bool {
        rehideTimer != nil || frontmostApplicationCancellable != nil
    }

    var activeTagIdentifiers: Set<String> {
        Set(contexts.map(\.tag.tagIdentifier))
    }

    var outstandingContexts: [MenuBarTemporaryRevealPolicy.OutstandingContext] {
        contexts.map {
            MenuBarTemporaryRevealPolicy.OutstandingContext(
                tag: $0.tag,
                rehideAttempts: $0.rehideAttempts
            )
        }
    }

    var cachePopulationContexts: [MenuBarCachePopulationPolicy.TemporaryContext] {
        contexts.map {
            MenuBarCachePopulationPolicy.TemporaryContext(
                tag: $0.tag,
                sourcePID: $0.sourcePID,
                originalSection: $0.originalSection,
                destination: $0.returnDestination
            )
        }
    }

    var relocationPlanningContexts: [PendingLedger.RehideContextObservation] {
        contexts.map {
            PendingLedger.RehideContextObservation(
                tag: $0.tag,
                fallbackNeighbor: $0.fallbackNeighborTag
            )
        }
    }

    mutating func append(_ context: MenuBarTemporaryRevealContext) {
        contexts.append(context)
    }

    mutating func drainContexts() -> [MenuBarTemporaryRevealContext] {
        let drained = contexts
        contexts.removeAll()
        return drained
    }

    mutating func restoreContexts(_ contexts: [MenuBarTemporaryRevealContext]) {
        self.contexts.append(contentsOf: contexts)
    }

    mutating func appendFailedContextsForRetry(_ contexts: [MenuBarTemporaryRevealContext]) {
        self.contexts.append(contentsOf: contexts.reversed())
    }

    mutating func removeContexts(matching tag: MenuBarItemTag) -> [MenuBarTemporaryRevealContext] {
        var removed = [MenuBarTemporaryRevealContext]()
        while let index = contexts.firstIndex(where: { $0.tag.matchesIgnoringWindowID(tag) }) {
            removed.append(contexts.remove(at: index))
        }
        return removed
    }

    mutating func clearContexts() {
        contexts.removeAll()
    }

    mutating func attachRehideTimer(_ timer: Timer) {
        rehideTimer = timer
    }

    mutating func attachFrontmostApplicationCancellable(_ cancellable: AnyCancellable) {
        frontmostApplicationCancellable = cancellable
    }

    mutating func cancelRehideTriggers() {
        rehideTimer?.invalidate()
        rehideTimer = nil
        frontmostApplicationCancellable?.cancel()
        frontmostApplicationCancellable = nil
    }

    mutating func cancelAll() {
        cancelRehideTriggers()
        clearContexts()
    }
}
