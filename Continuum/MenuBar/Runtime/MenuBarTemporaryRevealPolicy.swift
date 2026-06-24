//
//  MenuBarTemporaryRevealPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure routing policy for temporary reveal and rehide operations.
///
/// The manager still performs observation, moves, clicks, and persistence.
/// This policy owns the snapshot-only choices that keep a temporarily revealed
/// item returnable when neighboring menu-bar items disappear or relaunch.
enum MenuBarTemporaryRevealPolicy {
    struct Neighbor: Equatable {
        let tag: MenuBarItemTag
        let pid: pid_t
    }

    struct ReturnInfo: Equatable {
        let destination: MenuBarMoveDestination
        let fallbackNeighbor: Neighbor?
    }

    struct ReturnRoute: Equatable {
        let destination: MenuBarMoveDestination
        let fallbackNeighbor: Neighbor?
        let originalSection: MenuBarSection.Name
    }

    struct OutstandingContext: Equatable {
        let tag: MenuBarItemTag
        let rehideAttempts: Int
    }

    struct PendingMetadata: Equatable {
        let relocationValue: String
        let returnDestinationStorageValue: [String: String]
    }

    enum RevealAdmissionAfterForcedRehide: Equatable {
        case proceed(removeExistingMatchingContext: Bool)
        case block(stuckTags: [MenuBarItemTag])
    }

    enum ReturnDestinationSource: Equatable {
        case primaryNeighbor
        case fallbackNeighbor
        case sectionControl
    }

    struct ResolvedReturnDestination: Equatable {
        let destination: MenuBarMoveDestination
        let source: ReturnDestinationSource
    }

    enum MoveErrorMetadataDecision: Equatable {
        case preservePendingRelocation
        case discardPendingRelocation
    }

    enum PendingMetadataMutation: Equatable {
        case preserve(PendingMetadata)
        case discard
    }

    enum PositionSettleDecision: Equatable {
        case settled
        case keepWaiting(nextPreviousBounds: CGRect?)
    }

    enum OriginDepartureDecision: Equatable {
        case departed
        case keepWaiting
    }

    static func captureReturnInfo(
        for item: MenuBarItem,
        in items: [MenuBarItem]
    ) -> ReturnInfo? {
        guard let index = items.firstIndex(matching: item.tag) else {
            return nil
        }

        if items.indices.contains(index + 1) {
            let neighbor = items[index + 1]
            let fallback: Neighbor? = if items.indices.contains(index - 1) {
                makeNeighbor(from: items[index - 1])
            } else {
                nil
            }
            return ReturnInfo(
                destination: .leftOfItem(neighbor),
                fallbackNeighbor: fallback
            )
        }

        if items.indices.contains(index - 1) {
            return ReturnInfo(
                destination: .rightOfItem(items[index - 1]),
                fallbackNeighbor: nil
            )
        }

        return nil
    }

    static func revealAnchor(in items: [MenuBarItem]) -> MenuBarItem? {
        items.first(matching: .visibleControlItem) ??
            items.first(where: { !$0.isControlItem && $0.canBeHidden }) ??
            items.first
    }

    static func resolveReturnDestination(
        for route: ReturnRoute,
        in items: [MenuBarItem]
    ) -> ResolvedReturnDestination? {
        let targetTag = route.destination.targetItem.tag
        let targetPID = route.destination.targetItem.sourcePID ?? route.destination.targetItem.ownerPID
        if let freshTarget = items.first(where: {
            $0.tag.matchesIgnoringWindowID(targetTag) &&
                ($0.sourcePID ?? $0.ownerPID) == targetPID
        }) {
            return ResolvedReturnDestination(
                destination: route.destination.retargeted(to: freshTarget),
                source: .primaryNeighbor
            )
        }

        if let fallbackNeighbor = route.fallbackNeighbor,
           let freshFallback = items.first(where: {
               $0.tag.matchesIgnoringWindowID(fallbackNeighbor.tag) &&
                   ($0.sourcePID ?? $0.ownerPID) == fallbackNeighbor.pid
           })
        {
            return ResolvedReturnDestination(
                destination: route.destination.oppositeSide(of: freshFallback),
                source: .fallbackNeighbor
            )
        }

        return sectionFallbackDestination(
            for: route.originalSection,
            in: items
        ).map {
            ResolvedReturnDestination(
                destination: $0,
                source: .sectionControl
            )
        }
    }

    static func metadataDecisionAfterMoveError(
        preMoveOrigin: CGPoint?,
        currentOrigin: CGPoint?
    ) -> MoveErrorMetadataDecision {
        if currentOrigin == nil || preMoveOrigin == nil || currentOrigin != preMoveOrigin {
            return .preservePendingRelocation
        }
        return .discardPendingRelocation
    }

    static func pendingMetadata(
        originalSection: MenuBarSection.Name,
        returnDestination: MenuBarMoveDestination
    ) -> PendingMetadata {
        PendingMetadata(
            relocationValue: PendingLedger.sectionKey(for: originalSection),
            returnDestinationStorageValue: PendingLedger.makePendingReturnDestination(
                for: returnDestination
            ).storageValue
        )
    }

    static func pendingMetadataMutationAfterMoveError(
        preMoveOrigin: CGPoint?,
        currentOrigin: CGPoint?,
        metadata: PendingMetadata
    ) -> PendingMetadataMutation {
        switch metadataDecisionAfterMoveError(
            preMoveOrigin: preMoveOrigin,
            currentOrigin: currentOrigin
        ) {
        case .preservePendingRelocation:
            .preserve(metadata)
        case .discardPendingRelocation:
            .discard
        }
    }

    static func positionSettleDecision(
        previousBounds: CGRect?,
        currentBounds: CGRect?
    ) -> PositionSettleDecision {
        if let currentBounds, currentBounds == previousBounds {
            return .settled
        }

        return .keepWaiting(nextPreviousBounds: currentBounds)
    }

    static func originDepartureDecision(
        previousOrigin: CGPoint,
        currentOrigin: CGPoint?
    ) -> OriginDepartureDecision {
        guard let currentOrigin, currentOrigin != previousOrigin else {
            return .keepWaiting
        }

        return .departed
    }

    static func admissionAfterForcedRehide(
        outstandingContexts: [OutstandingContext],
        requestedTag: MenuBarItemTag
    ) -> RevealAdmissionAfterForcedRehide {
        let stuckTags = outstandingContexts.compactMap { context in
            if !context.tag.matchesIgnoringWindowID(requestedTag), context.rehideAttempts > 0 {
                return context.tag
            }
            return nil
        }

        if !stuckTags.isEmpty {
            return .block(stuckTags: stuckTags)
        }

        return .proceed(
            removeExistingMatchingContext: outstandingContexts.contains {
                $0.tag.matchesIgnoringWindowID(requestedTag)
            }
        )
    }

    private static func makeNeighbor(from item: MenuBarItem) -> Neighbor {
        Neighbor(
            tag: item.tag,
            pid: item.sourcePID ?? item.ownerPID
        )
    }

    private static func sectionFallbackDestination(
        for section: MenuBarSection.Name,
        in items: [MenuBarItem]
    ) -> MenuBarMoveDestination? {
        switch section {
        case .hidden:
            if let controlItem = items.first(matching: .hiddenControlItem) {
                return .leftOfItem(controlItem)
            }
        case .alwaysHidden:
            if let controlItem = items.first(matching: .alwaysHiddenControlItem) {
                return .leftOfItem(controlItem)
            }
            if let controlItem = items.first(matching: .hiddenControlItem) {
                return .leftOfItem(controlItem)
            }
        case .visible:
            return nil
        }
        return nil
    }
}

private extension MenuBarMoveDestination {
    func retargeted(to item: MenuBarItem) -> MenuBarMoveDestination {
        switch self {
        case .leftOfItem:
            .leftOfItem(item)
        case .rightOfItem:
            .rightOfItem(item)
        }
    }

    func oppositeSide(of item: MenuBarItem) -> MenuBarMoveDestination {
        switch self {
        case .leftOfItem:
            .rightOfItem(item)
        case .rightOfItem:
            .leftOfItem(item)
        }
    }
}
