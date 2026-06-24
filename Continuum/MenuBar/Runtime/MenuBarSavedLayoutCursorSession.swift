//
//  MenuBarSavedLayoutCursorSession.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Owns the cursor lifecycle for one saved-layout apply pass.
///
/// Saved-layout apply deliberately suppresses per-move cursor management so a
/// long sequence of synthetic drags hides the cursor once, restores it once,
/// and does not flash the pointer between individual moves.
struct MenuBarSavedLayoutCursorSession: Equatable {
    static let watchdogTimeout: DispatchTimeInterval = .seconds(30)

    let savedPosition: CGPoint

    @discardableResult
    static func begin(
        mouseLocation: CGPoint,
        hideCursor: (DispatchTimeInterval?) -> Void,
        beginSuppression: () -> Void
    ) -> MenuBarSavedLayoutCursorSession {
        hideCursor(watchdogTimeout)
        beginSuppression()
        return MenuBarSavedLayoutCursorSession(savedPosition: mouseLocation)
    }

    func finish(
        screenFrames: [CGRect],
        fallbackScreenFrame: CGRect?,
        endSuppression: () -> Void,
        warpCursor: (CGPoint) -> Void,
        showCursor: () -> Void
    ) {
        if let point = Self.restorationPoint(
            for: savedPosition,
            screenFrames: screenFrames,
            fallbackScreenFrame: fallbackScreenFrame
        ) {
            warpCursor(point)
        }
        endSuppression()
        showCursor()
    }

    static func restorationPoint(
        for savedPosition: CGPoint,
        screenFrames: [CGRect],
        fallbackScreenFrame: CGRect?
    ) -> CGPoint? {
        guard let screen = screenFrames.first(where: { $0.contains(savedPosition) }) ?? fallbackScreenFrame else {
            return nil
        }
        let cgY = screen.origin.y + screen.height - savedPosition.y
        return MenuBarMoveGeometryPolicy.hotCornerSafePoint(
            CGPoint(x: savedPosition.x, y: cgY),
            screenFrames: screenFrames
        )
    }
}
