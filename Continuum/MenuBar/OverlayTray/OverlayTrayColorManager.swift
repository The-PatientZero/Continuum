//
//  OverlayTrayColorManager.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine

@MainActor
final class OverlayTrayColorManager: ObservableObject {
    @Published private(set) var colorInfo: MenuBarAverageColorInfo?

    func performSetup(with _: OverlayTrayPanel) {
        colorInfo = nil
    }

    func updateAllProperties(with _: CGRect, screen _: NSScreen) {
        colorInfo = nil
    }
}
