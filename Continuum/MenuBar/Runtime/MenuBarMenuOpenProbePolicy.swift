//
//  MenuBarMenuOpenProbePolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Pure policy for the "is any menu bar menu open?" probe.
///
/// The manager owns WindowServer enumeration and source-PID resolution. This
/// type owns the bounded positive-result cache, cheap PID fast path, and the
/// precise fallback trigger so smart rehide remains lightweight under churn.
enum MenuBarMenuOpenProbePolicy {
    static let positiveCacheFreshness: Duration = .milliseconds(250)

    enum CachedResultDecision: Equatable, Sendable {
        case useCachedOpenMenu
        case probe
    }

    struct ItemObservation: Equatable, Sendable {
        let windowID: CGWindowID
        let ownerPID: pid_t
        let sourcePID: pid_t?
        let ownerBundleIdentifier: String?
        let isControlItem: Bool
        let isOnScreen: Bool
    }

    struct WindowObservation: Equatable, Sendable {
        let windowID: CGWindowID
        let ownerPID: pid_t
        let ownerBundleIdentifier: String?
        let title: String?
        let isMenuRelated: Bool
    }

    struct FastPathEvaluation: Equatable, Sendable {
        let candidateMenuWindows: [WindowObservation]
        let fastPathPIDs: Set<pid_t>
        let openMenuOwnerPID: pid_t?
        let unresolvedWindowIDs: [CGWindowID]

        var needsPreciseFallback: Bool {
            openMenuOwnerPID == nil && !unresolvedWindowIDs.isEmpty
        }
    }

    static func cachedResultDecision(
        cachedResult: Bool?,
        cachedAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant = .now
    ) -> CachedResultDecision {
        guard cachedResult == true,
              let cachedAt,
              cachedAt.duration(to: now) <= positiveCacheFreshness
        else {
            return .probe
        }
        return .useCachedOpenMenu
    }

    static func candidateMenuWindows(
        from windows: [WindowObservation],
        controlCenterBundleIdentifier: String
    ) -> [WindowObservation] {
        windows.filter { window in
            guard window.isMenuRelated, window.title?.isEmpty ?? true else {
                return false
            }
            return window.ownerBundleIdentifier != controlCenterBundleIdentifier
        }
    }

    static func fastPathEvaluation(
        cachedItems: [ItemObservation],
        candidateMenuWindows: [WindowObservation],
        controlCenterBundleIdentifier: String
    ) -> FastPathEvaluation {
        let fastPathPIDs = fastPathCandidatePIDs(
            from: cachedItems,
            controlCenterBundleIdentifier: controlCenterBundleIdentifier
        )
        return FastPathEvaluation(
            candidateMenuWindows: candidateMenuWindows,
            fastPathPIDs: fastPathPIDs,
            openMenuOwnerPID: openMenuOwnerPID(
                in: candidateMenuWindows,
                candidatePIDs: fastPathPIDs
            ),
            unresolvedWindowIDs: unresolvedControlCenterWindowIDs(
                from: cachedItems,
                controlCenterBundleIdentifier: controlCenterBundleIdentifier
            )
        )
    }

    static func preciseFallbackOpenMenuOwnerPID(
        candidateMenuWindows: [WindowObservation],
        fastPathPIDs: Set<pid_t>,
        resolvedPIDs: Set<pid_t>
    ) -> pid_t? {
        openMenuOwnerPID(
            in: candidateMenuWindows,
            candidatePIDs: fastPathPIDs.union(resolvedPIDs)
        )
    }

    private static func fastPathCandidatePIDs(
        from items: [ItemObservation],
        controlCenterBundleIdentifier: String
    ) -> Set<pid_t> {
        items.reduce(into: Set<pid_t>()) { result, item in
            guard item.isOnScreen else {
                return
            }
            if let sourcePID = item.sourcePID {
                result.insert(sourcePID)
                return
            }
            guard item.ownerBundleIdentifier != controlCenterBundleIdentifier else {
                return
            }
            result.insert(item.ownerPID)
        }
    }

    private static func unresolvedControlCenterWindowIDs(
        from items: [ItemObservation],
        controlCenterBundleIdentifier: String
    ) -> [CGWindowID] {
        items.compactMap { item in
            guard item.isOnScreen,
                  item.sourcePID == nil,
                  !item.isControlItem,
                  item.ownerBundleIdentifier == controlCenterBundleIdentifier
            else {
                return nil
            }
            return item.windowID
        }
    }

    private static func openMenuOwnerPID(
        in windows: [WindowObservation],
        candidatePIDs: Set<pid_t>
    ) -> pid_t? {
        windows.first { candidatePIDs.contains($0.ownerPID) }?.ownerPID
    }
}
