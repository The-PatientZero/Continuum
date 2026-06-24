//
//  MenuBarAccessibilityPressPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure policy for choosing which Accessibility child should receive an AX
/// press for a menu bar item.
///
/// The manager owns AX element lookup and the press itself. This policy owns
/// the deterministic matching rule used when Electron-style tray items ignore
/// synthetic click events.
enum MenuBarAccessibilityPressPolicy {
    static let maximumFrameCenterDistance: CGFloat = 10

    struct Candidate: Equatable {
        let index: Int
        let frame: CGRect?
    }

    enum TargetDecision: Equatable {
        case noTarget
        case useCandidate(index: Int)
    }

    static func targetCandidate(
        for itemBounds: CGRect,
        candidates: [Candidate]
    ) -> TargetDecision {
        guard !candidates.isEmpty else {
            return .noTarget
        }

        if candidates.count == 1 {
            return .useCandidate(index: candidates[0].index)
        }

        let itemCenter = itemBounds.center
        let best = candidates
            .compactMap { candidate -> (index: Int, distance: CGFloat)? in
                candidate.frame.map {
                    (candidate.index, $0.center.distance(to: itemCenter))
                }
            }
            .min { lhs, rhs in
                lhs.distance < rhs.distance
            }

        guard let best, best.distance <= maximumFrameCenterDistance else {
            return .noTarget
        }

        return .useCandidate(index: best.index)
    }
}
