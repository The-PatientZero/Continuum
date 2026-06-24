//
//  MenuBarMoveGeometryPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure geometry policy for synthesized move events.
///
/// The manager owns live bounds lookup, screen enumeration, cursor warping, and
/// event posting. This policy owns deterministic coordinates so the CGEvent
/// edge stays small and the notch/offscreen behavior is testable.
enum MenuBarMoveGeometryPolicy {
    struct EventPoints: Equatable {
        let start: CGPoint
        let end: CGPoint
    }

    enum CursorWarpDecision: Equatable {
        case warpAndSettle
        case skipWarp

        var shouldWarpCursor: Bool {
            self == .warpAndSettle
        }

        var shouldWaitForWarpSettle: Bool {
            self == .warpAndSettle
        }
    }

    static func eventPoints(
        for destination: MenuBarMoveDestination,
        targetBounds: CGRect
    ) -> EventPoints {
        let point: CGPoint = switch destination {
        case .leftOfItem:
            CGPoint(x: targetBounds.minX, y: targetBounds.minY)
        case .rightOfItem:
            CGPoint(x: targetBounds.maxX, y: targetBounds.minY)
        }

        return EventPoints(start: point, end: point)
    }

    static func cursorWarpDecision(
        warpPoint: CGPoint,
        screenFrames: [CGRect]
    ) -> CursorWarpDecision {
        screenFrames.contains { $0.contains(warpPoint) } ? .warpAndSettle : .skipWarp
    }

    static func mouseDownLocation(
        originalLocation: CGPoint,
        warpDecision: CursorWarpDecision,
        activeScreenNotchFrame: CGRect?
    ) -> CGPoint {
        guard warpDecision == .skipWarp, let activeScreenNotchFrame else {
            return originalLocation
        }

        return CGPoint(
            x: activeScreenNotchFrame.midX,
            y: activeScreenNotchFrame.midY
        )
    }
}
