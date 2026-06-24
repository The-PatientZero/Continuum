//
//  MenuBarTemporaryRevealResult.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Result of a temporary reveal operation.
///
/// The value distinguishes a failed reveal from the narrower case where the
/// icon reached the visible area but the synthetic click failed, which lets
/// UI callers reason about fallback behavior without depending on manager
/// internals.
enum MenuBarTemporaryRevealResult: Equatable {
    /// The item was never moved; a precondition failed (missing state,
    /// no return destination, no anchor, or the move itself failed).
    /// The item is still hidden; do not attempt a fallback click.
    case showFailed
    /// The item was moved into the visible area and the synthetic click
    /// completed successfully.
    case movedAndClicked
    /// The item was moved into the visible area but the synthetic click
    /// failed. The icon is now visible; callers may attempt a fallback
    /// click using live bounds.
    case movedButClickFailed
}
