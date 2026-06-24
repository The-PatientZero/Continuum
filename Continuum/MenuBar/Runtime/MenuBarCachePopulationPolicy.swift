//
//  MenuBarCachePopulationPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Darwin

/// Pure policy for admitting observed items into the runtime cache population
/// pass.
///
/// The manager owns logging, Window Server bounds lookup, and cache mutation.
/// This policy owns deterministic admission, duplicate suppression, temporary
/// reveal masking, and no-section fallback decisions.
enum MenuBarCachePopulationPolicy {
    enum AdmissionDecision: Equatable {
        case rejectUncacheable
        case rejectDuplicate
        case admit
    }

    enum NoSectionFallback: Equatable {
        case skipBlocked
        case cacheInHidden
    }

    struct TemporaryContext: Equatable {
        let tag: MenuBarItemTag
        let sourcePID: pid_t
        let originalSection: MenuBarSection.Name
        let destination: MenuBarMoveDestination
    }

    static func admissionDecision(
        for item: MenuBarItem,
        seenTags: Set<MenuBarItemTag>
    ) -> AdmissionDecision {
        guard MenuBarSectionClassificationPolicy.isCacheable(item) else {
            return .rejectUncacheable
        }
        guard !seenTags.contains(item.tag) else {
            return .rejectDuplicate
        }
        return .admit
    }

    static func temporaryDestination(
        for item: MenuBarItem,
        currentSection: MenuBarSection.Name?,
        contexts: [TemporaryContext]
    ) -> MenuBarMoveDestination? {
        if let exact = contexts.first(where: { $0.tag == item.tag }) {
            return exact.destination
        }

        let effectiveSourcePID = item.sourcePID ?? item.ownerPID
        guard currentSection == .visible else {
            return nil
        }

        return contexts.first { context in
            context.tag.matchesIgnoringWindowID(item.tag) &&
                context.sourcePID == effectiveSourcePID &&
                context.originalSection != .visible
        }?.destination
    }

    static func noSectionFallback(for itemBounds: CGRect) -> NoSectionFallback {
        itemBounds.origin.x == -1 ? .skipBlocked : .cacheInHidden
    }
}
