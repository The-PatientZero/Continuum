//
//  MenuBarPopupVisibilityPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics

/// Pure visibility policy for menus opened from temporarily revealed items.
///
/// The manager still performs WindowServer and NSRunningApplication reads. This
/// policy owns the classification rules so rehide waits on real menus without
/// getting pinned forever by unrelated floating windows.
enum MenuBarPopupVisibilityPolicy {
    static let graceInterval: TimeInterval = 2
    static let minimumPopupHeight: CGFloat = 40

    struct WindowObservation: Equatable {
        let ownerPID: pid_t
        let layer: Int
        let bounds: CGRect
        let isOnScreen: Bool
        let appActivationPolicy: NSApplication.ActivationPolicy?
        let appIsActive: Bool?
    }

    static func trackedWindowIsShowing(_ window: WindowObservation) -> Bool {
        if isDirectMenuLevel(window.layer) {
            return window.isOnScreen
        }

        guard let appActivationPolicy = window.appActivationPolicy,
              let appIsActive = window.appIsActive
        else {
            return window.isOnScreen
        }

        if appActivationPolicy == .accessory || isMenuSized(window) {
            return window.isOnScreen
        }

        return appIsActive && window.isOnScreen
    }

    static func shouldAssumeShowingDuringGrace(
        firstShownAt: Date,
        now: Date = Date(),
        graceInterval: TimeInterval = Self.graceInterval
    ) -> Bool {
        now.timeIntervalSince(firstShownAt) < graceInterval
    }

    static func appHasVisiblePopup(
        sourcePID: pid_t,
        windows: [WindowObservation]
    ) -> Bool {
        windows.contains { window in
            guard window.ownerPID == sourcePID, window.isOnScreen else {
                return false
            }

            if isPopupLevel(window.layer) {
                return true
            }

            if isStatusOrMainMenuLevel(window.layer) {
                return isMenuSized(window)
            }

            return false
        }
    }

    private static func isDirectMenuLevel(_ layer: Int) -> Bool {
        isPopupLevel(layer) || isStatusOrMainMenuLevel(layer)
    }

    private static func isPopupLevel(_ layer: Int) -> Bool {
        let level = CGWindowLevel(Int32(layer))
        return level == CGWindowLevelForKey(.popUpMenuWindow) ||
            level == CGWindowLevelForKey(.popUpMenuWindow) - 1
    }

    private static func isStatusOrMainMenuLevel(_ layer: Int) -> Bool {
        let level = CGWindowLevel(Int32(layer))
        return level == CGWindowLevelForKey(.statusWindow) ||
            level == CGWindowLevelForKey(.mainMenuWindow)
    }

    private static func isMenuSized(_ window: WindowObservation) -> Bool {
        window.bounds.height > minimumPopupHeight
    }
}
