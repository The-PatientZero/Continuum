//
//  MenuBarTemporaryRevealContext.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import CoreGraphics
import Foundation

/// Runtime context for one temporarily revealed menu bar item.
///
/// The context keeps the stable return route, retry counters, and popup-window
/// observation needed by rehide. Movement and persistence stay with the manager.
final class MenuBarTemporaryRevealContext {
    let tag: MenuBarItemTag
    let sourcePID: pid_t
    let displayID: CGDirectDisplayID
    let returnRoute: MenuBarTemporaryRevealPolicy.ReturnRoute

    var returnDestination: MenuBarMoveDestination {
        returnRoute.destination
    }

    var fallbackNeighborTag: MenuBarItemTag? {
        returnRoute.fallbackNeighbor?.tag
    }

    var originalSection: MenuBarSection.Name {
        returnRoute.originalSection
    }

    var shownInterfaceWindow: WindowInfo?
    var rehideAttempts = 0
    var notFoundAttempts = 0

    private let firstShownDate = Date.now
    private let graceInterval: TimeInterval = 2

    var isShowingInterface: Bool {
        if let window = shownInterfaceWindow,
           let current = WindowInfo(windowID: window.windowID)
        {
            return MenuBarPopupVisibilityPolicy.trackedWindowIsShowing(
                observation(for: current)
            )
        }

        if MenuBarPopupVisibilityPolicy.shouldAssumeShowingDuringGrace(
            firstShownAt: firstShownDate,
            now: Date.now,
            graceInterval: graceInterval
        ) {
            return true
        }

        return appHasVisiblePopup()
    }

    init(
        tag: MenuBarItemTag,
        sourcePID: pid_t,
        displayID: CGDirectDisplayID,
        returnRoute: MenuBarTemporaryRevealPolicy.ReturnRoute
    ) {
        self.tag = tag
        self.sourcePID = sourcePID
        self.displayID = displayID
        self.returnRoute = returnRoute
    }

    private func appHasVisiblePopup() -> Bool {
        let windows = WindowInfo.createWindows(option: .onScreen)
        return MenuBarPopupVisibilityPolicy.appHasVisiblePopup(
            sourcePID: sourcePID,
            windows: windows.map(observation(for:))
        )
    }

    private func observation(
        for window: WindowInfo
    ) -> MenuBarPopupVisibilityPolicy.WindowObservation {
        let app = window.owningApplication
        return MenuBarPopupVisibilityPolicy.WindowObservation(
            ownerPID: window.ownerPID,
            layer: window.layer,
            bounds: window.bounds,
            isOnScreen: window.isOnScreen,
            appActivationPolicy: app?.activationPolicy,
            appIsActive: app?.isActive
        )
    }
}
