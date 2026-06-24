//
//  MenuBarCacheCycleContinuationExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Executes the post-observation branch of one cache cycle.
///
/// Observation and control-item discovery stay in the manager because they touch
/// live WindowServer state. Once controls are resolved, this executor owns the
/// deterministic continuation: control ordering, relocation follow-up decisions,
/// saved-layout restore dispatch, cache commit, and source-PID baseline updates.
enum MenuBarCacheCycleContinuationExecutor {
    enum StopReason: Equatable {
        case cancelledAfterControlDiscovery
        case cancelledBeforeRelocation
        case followUpRecacheScheduled(MenuBarCacheCyclePolicy.RelocationReason)
        case savedLayoutApplied
        case cachedObservation(MenuBarCacheCyclePolicy.CacheObservationReason)
        case committedCache
    }

    struct Input {
        let items: [MenuBarItem]
        let controlItems: MenuBarControlItems
        let previousWindowIDs: [CGWindowID]
        let previousDisplayID: CGDirectDisplayID?
        let currentDisplayID: CGDirectDisplayID?
        let isInStartupSettling: Bool
        let skipSavedLayoutApply: Bool
        let resolveSourcePID: Bool
    }

    struct Outcome: Equatable {
        let stopReason: StopReason
    }

    struct Operations {
        let taskIsCancelled: () -> Bool
        let enforceControlItemOrder: (MenuBarControlItems) async -> Void
        let relocateNewLeftmostItems: (
            [MenuBarItem],
            MenuBarControlItems,
            [CGWindowID]
        ) async -> Bool
        let relocatePendingItems: ([MenuBarItem], MenuBarControlItems) async -> Bool
        let scheduleFollowUpRecache: (MenuBarCacheCyclePolicy.RelocationReason) -> Void
        let cacheObservation: (
            [MenuBarItem],
            MenuBarControlItems,
            CGDirectDisplayID?
        ) async -> Void
        let applySavedLayout: (
            [MenuBarItem],
            [CGWindowID],
            MenuBarControlItems,
            CGDirectDisplayID?,
            CGDirectDisplayID?
        ) async -> Bool
        let recordResolvedSourcePIDs: ([CGWindowID: pid_t]) -> Void
    }

    struct Diagnostics {
        var recordCancelledAfterControlDiscovery: () -> Void = {}
        var recordCancelledBeforeRelocation: () -> Void = {}
        var recordStartupSettlingCached: () -> Void = {}
    }

    @MainActor
    static func execute(
        input: Input,
        operations: Operations,
        diagnostics: Diagnostics = Diagnostics()
    ) async -> Outcome {
        guard !operations.taskIsCancelled() else {
            diagnostics.recordCancelledAfterControlDiscovery()
            return Outcome(stopReason: .cancelledAfterControlDiscovery)
        }

        await operations.enforceControlItemOrder(input.controlItems)

        guard !operations.taskIsCancelled() else {
            diagnostics.recordCancelledBeforeRelocation()
            return Outcome(stopReason: .cancelledBeforeRelocation)
        }

        let newLeftmostItemsRelocated = await operations.relocateNewLeftmostItems(
            input.items,
            input.controlItems,
            input.previousWindowIDs
        )
        switch MenuBarCacheCyclePolicy.relocationFollowUpDecision(
            newLeftmostItemsRelocated: newLeftmostItemsRelocated,
            pendingItemsRelocated: false
        ) {
        case .continueCycle:
            break
        case let .scheduleRecache(reason):
            operations.scheduleFollowUpRecache(reason)
            return Outcome(stopReason: .followUpRecacheScheduled(reason))
        }

        let pendingItemsRelocated = await operations.relocatePendingItems(
            input.items,
            input.controlItems
        )
        switch MenuBarCacheCyclePolicy.relocationFollowUpDecision(
            newLeftmostItemsRelocated: false,
            pendingItemsRelocated: pendingItemsRelocated
        ) {
        case .continueCycle:
            break
        case let .scheduleRecache(reason):
            operations.scheduleFollowUpRecache(reason)
            return Outcome(stopReason: .followUpRecacheScheduled(reason))
        }

        switch MenuBarCacheCyclePolicy.postRelocationDecision(
            isInStartupSettling: input.isInStartupSettling,
            skipSavedLayoutApply: input.skipSavedLayoutApply
        ) {
        case .cacheObservation(.startupSettling):
            await operations.cacheObservation(
                input.items,
                input.controlItems,
                input.currentDisplayID
            )
            diagnostics.recordStartupSettlingCached()
            return Outcome(stopReason: .cachedObservation(.startupSettling))

        case .cacheObservation(.savedLayoutApplySkipped):
            break

        case .evaluateSavedLayout:
            let didApplySavedLayout = await operations.applySavedLayout(
                input.items,
                input.previousWindowIDs,
                input.controlItems,
                input.previousDisplayID,
                input.currentDisplayID
            )
            if didApplySavedLayout {
                return Outcome(stopReason: .savedLayoutApplied)
            }
        }

        await operations.cacheObservation(
            input.items,
            input.controlItems,
            input.currentDisplayID
        )

        if MenuBarCacheCyclePolicy.shouldRecordResolvedSourcePIDs(
            resolveSourcePID: input.resolveSourcePID
        ) {
            operations.recordResolvedSourcePIDs(sourcePIDs(from: input.items))
        }

        return Outcome(stopReason: .committedCache)
    }

    private static func sourcePIDs(from items: [MenuBarItem]) -> [CGWindowID: pid_t] {
        Dictionary(
            uniqueKeysWithValues: items.compactMap { item in
                item.sourcePID.map { (item.windowID, $0) }
            }
        )
    }
}
