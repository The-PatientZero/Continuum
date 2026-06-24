//
//  MenuBarCacheCyclePolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Pure policy for cache-cycle continuation decisions after WindowServer
/// observation.
///
/// The manager still owns observing, moving, diagnostics, and cache mutation.
/// This policy owns the deterministic control-flow choices that keep one
/// cache cycle from cascading into unstable restore/apply loops.
enum MenuBarCacheCyclePolicy {
    enum ControlItemDecision: Equatable {
        case continueCycle
        case preserveKnownGoodCache
    }

    enum RelocationReason: Equatable, CustomStringConvertible {
        case newLeftmostItems
        case pendingItems

        var description: String {
            switch self {
            case .newLeftmostItems:
                "new leftmost items relocated"
            case .pendingItems:
                "pending temporarily-shown items relocated"
            }
        }
    }

    enum RelocationFollowUpDecision: Equatable {
        case continueCycle
        case scheduleRecache(RelocationReason)
    }

    enum CacheObservationReason: Equatable {
        case startupSettling
        case savedLayoutApplySkipped
    }

    enum PostRelocationDecision: Equatable {
        case cacheObservation(CacheObservationReason)
        case evaluateSavedLayout
    }

    static func controlItemDecision(controlItemsFound: Bool) -> ControlItemDecision {
        controlItemsFound ? .continueCycle : .preserveKnownGoodCache
    }

    static func relocationFollowUpDecision(
        newLeftmostItemsRelocated: Bool,
        pendingItemsRelocated: Bool
    ) -> RelocationFollowUpDecision {
        if newLeftmostItemsRelocated {
            return .scheduleRecache(.newLeftmostItems)
        }
        if pendingItemsRelocated {
            return .scheduleRecache(.pendingItems)
        }
        return .continueCycle
    }

    static func postRelocationDecision(
        isInStartupSettling: Bool,
        skipSavedLayoutApply: Bool
    ) -> PostRelocationDecision {
        if isInStartupSettling {
            return .cacheObservation(.startupSettling)
        }
        if skipSavedLayoutApply {
            return .cacheObservation(.savedLayoutApplySkipped)
        }
        return .evaluateSavedLayout
    }

    static func shouldRecordResolvedSourcePIDs(resolveSourcePID: Bool) -> Bool {
        resolveSourcePID
    }
}
