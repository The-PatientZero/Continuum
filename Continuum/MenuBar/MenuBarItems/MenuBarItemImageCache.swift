//
//  MenuBarItemImageCache.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine

/// Passive image cache facade for menu bar item UI.
///
/// Continuum intentionally does not capture menu bar windows. The inherited
/// screenshot-backed cache required screen capture permission,
/// and a live refresh loop. Keeping this type as a small inert facade preserves
/// the existing view contracts while making screen observation impossible here.
final class MenuBarItemImageCache: ObservableObject, @unchecked Sendable {
    private static nonisolated let diagLog = DiagLog(category: "MenuBarItemImageCache")
    static let capturesScreenContent = false

    /// A representation of a menu bar item image.
    struct CapturedImage: Hashable {
        let cgImage: CGImage
        let scale: CGFloat

        var scaledSize: CGSize {
            CGSize(
                width: CGFloat(cgImage.width) / scale,
                height: CGFloat(cgImage.height) / scale
            )
        }

        var nsImage: NSImage {
            NSImage(cgImage: cgImage, size: scaledSize)
        }

        static func isVisuallyEqual(_ old: CapturedImage?, _ new: CapturedImage?) -> Bool {
            guard let old, let new else { return old == nil && new == nil }
            return old.cgImage === new.cgImage &&
                old.scale == new.scale &&
                old.cgImage.width == new.cgImage.width &&
                old.cgImage.height == new.cgImage.height
        }
    }

    @Published private(set) var images = [MenuBarItemTag: CapturedImage]()
    @Published private(set) var settingsPaneHasBeenOpened = false
    @Published private(set) var isItemHotkeyListExpanded = false

    struct NavigationStateSnapshot {
        let isOverlayTrayPresented: Bool
        let isAppFrontmost: Bool
        let isSettingsPresented: Bool
        let settingsNavigationIdentifier: SettingsNavigationIdentifier?
        let isItemHotkeyListExpanded: Bool
    }

    @MainActor
    func performSetup(with _: AppState) {
        clearAll()
    }

    @MainActor
    func markSettingsPaneOpened() {
        settingsPaneHasBeenOpened = true
    }

    @MainActor
    func setItemHotkeyListExpanded(_ expanded: Bool) {
        isItemHotkeyListExpanded = expanded
    }

    func image(for _: MenuBarItemTag) -> CapturedImage? {
        nil
    }

    var cacheSize: Int {
        images.count
    }

    var lruEntryCount: Int {
        0
    }

    @MainActor
    func performCacheCleanup() {
        clearAll()
    }

    func logCacheStatus(_ context: String = "Manual check") {
        Self.diagLog.info("Image cache disabled: \(context)")
    }

    @MainActor
    func updateCacheWithoutChecks(sections _: [MenuBarSection.Name]) async {}

    func updateCache(
        sections _: [MenuBarSection.Name],
        skipRecentMoveCheck _: Bool = false,
        allowBackgroundCapture _: Bool = false,
        nav _: NavigationStateSnapshot? = nil
    ) async {}

    @MainActor
    func updateCache(nav _: NavigationStateSnapshot? = nil) async {}

    @MainActor
    func clearImages(for _: MenuBarSection.Name) {
        images.removeAll()
    }

    @MainActor
    func clearAll() {
        images.removeAll()
    }

    @MainActor
    func cacheFailed(for _: MenuBarSection.Name) -> Bool {
        false
    }
}
