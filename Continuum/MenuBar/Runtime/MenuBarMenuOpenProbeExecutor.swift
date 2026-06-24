//
//  MenuBarMenuOpenProbeExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Live executor for the "is any menu open?" probe used by smart rehide.
///
/// The policy owns the pure PID/window matching rules and
/// ``MenuBarMenuOpenProbeRuntime`` owns caching and in-flight task sharing.
/// This executor owns the WindowServer scan and precise source-PID fallback.
enum MenuBarMenuOpenProbeExecutor {
    private static let diagLog = DiagLog(category: "MenuBarMenuOpenProbe")

    static func probe(
        cachedItems: [MenuBarItem],
        controlCenterBundleIdentifier: String = MenuBarItemTag.Namespace.controlCenter.description
    ) async -> Bool {
        let cachedItemObservations = cachedItems.map(itemObservation)
        let windows = WindowInfo.createWindows(option: .onScreen)
        let potentialMenuWindowObservations = MenuBarMenuOpenProbePolicy.candidateMenuWindows(
            from: windows.map(windowObservation),
            controlCenterBundleIdentifier: controlCenterBundleIdentifier
        )

        guard !potentialMenuWindowObservations.isEmpty else {
            diagLog.debug("Menu open check: no candidate menu windows on screen")
            return false
        }

        let candidateWindowIDs = Set(potentialMenuWindowObservations.map(\.windowID))
        let potentialMenuWindows = windows.filter {
            candidateWindowIDs.contains($0.windowID)
        }
        let fastPathEvaluation = MenuBarMenuOpenProbePolicy.fastPathEvaluation(
            cachedItems: cachedItemObservations,
            candidateMenuWindows: potentialMenuWindowObservations,
            controlCenterBundleIdentifier: controlCenterBundleIdentifier
        )

        diagLog.debug(
            """
            Checking for open menus - fast path with \(cachedItems.count) cached menu bar items, \
            \(fastPathEvaluation.fastPathPIDs.count) candidate PIDs, \
            \(potentialMenuWindows.count) candidate menu windows
            """
        )

        if let openMenuOwnerPID = fastPathEvaluation.openMenuOwnerPID {
            if let window = potentialMenuWindows.first(where: { $0.ownerPID == openMenuOwnerPID }) {
                logOpenMenuWindow(window, context: "fast path")
            }
            diagLog.debug("Menu open check result: true (fast path)")
            return true
        }

        guard fastPathEvaluation.needsPreciseFallback else {
            diagLog.debug("Menu open check result: false (fast path)")
            return false
        }

        let unresolvedWindows = WindowInfo.createWindows(
            from: fastPathEvaluation.unresolvedWindowIDs
        )

        diagLog.debug(
            "Menu open check: precise fallback resolving \(unresolvedWindows.count) unresolved window source PIDs"
        )

        let resolvedPIDs = await resolveAllSourcePIDs(for: unresolvedWindows)
        let preciseOpenMenuOwnerPID = MenuBarMenuOpenProbePolicy.preciseFallbackOpenMenuOwnerPID(
            candidateMenuWindows: potentialMenuWindowObservations,
            fastPathPIDs: fastPathEvaluation.fastPathPIDs,
            resolvedPIDs: resolvedPIDs
        )
        if let preciseOpenMenuOwnerPID,
           let window = potentialMenuWindows.first(where: { $0.ownerPID == preciseOpenMenuOwnerPID })
        {
            logOpenMenuWindow(window, context: "precise fallback")
        }
        let result = preciseOpenMenuOwnerPID != nil

        diagLog.debug(
            "Menu open check result: \(result) (precise fallback with \(resolvedPIDs.count) resolved PIDs)"
        )
        return result
    }

    static func itemObservation(
        for item: MenuBarItem
    ) -> MenuBarMenuOpenProbePolicy.ItemObservation {
        MenuBarMenuOpenProbePolicy.ItemObservation(
            windowID: item.windowID,
            ownerPID: item.ownerPID,
            sourcePID: item.sourcePID,
            ownerBundleIdentifier: item.owningApplication?.bundleIdentifier,
            isControlItem: item.isControlItem,
            isOnScreen: item.isOnScreen
        )
    }

    private static func windowObservation(
        for window: WindowInfo
    ) -> MenuBarMenuOpenProbePolicy.WindowObservation {
        MenuBarMenuOpenProbePolicy.WindowObservation(
            windowID: window.windowID,
            ownerPID: window.ownerPID,
            ownerBundleIdentifier: window.owningApplication?.bundleIdentifier,
            title: window.title,
            isMenuRelated: window.isMenuRelated
        )
    }

    private static func resolveAllSourcePIDs(for windows: [WindowInfo]) async -> Set<pid_t> {
        let pids = await MenuBarItem.sourcePIDsResolvingInProcess(for: windows)
        return Set(pids.compactMap(\.self))
    }

    private static func logOpenMenuWindow(
        _ window: WindowInfo,
        context: String
    ) {
        diagLog.debug(
            """
            Found open menu window on \(context): PID \(window.ownerPID), \
            owner: \(window.ownerName as NSObject?), title: \(window.title ?? "nil"), \
            isMenuRelated: \(window.isMenuRelated)
            """
        )
    }
}
