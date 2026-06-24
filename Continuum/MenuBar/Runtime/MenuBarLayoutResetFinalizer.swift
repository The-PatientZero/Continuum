//
//  MenuBarLayoutResetFinalizer.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Finalizes a successful layout reset after reset moves have completed.
///
/// The manager owns concrete cache and image stores. This finalizer owns the
/// post-reset sequence: clear cache state, run a fresh cache rebuild, clear
/// temporary suppression, rebuild images, publish UI changes, and invalidate
/// stale menu bar height probes.
enum MenuBarLayoutResetFinalizer {
    enum ImageRefreshPath: Equatable {
        case immediate
        case fallbackAfterCacheMiss
    }

    struct Outcome: Equatable {
        let imageRefreshPath: ImageRefreshPath
    }

    struct Operations {
        let clearCacheLedger: () -> Void
        let resetItemCache: () -> Void
        let storeBackgroundContinuation: (CheckedContinuation<Void, Never>) -> Void
        let startCacheRebuild: () -> Void
        let clearNewItemSuppression: () -> Void
        let clearImageCache: () -> Void
        let cleanupImageCache: () -> Void
        let itemCacheHasDisplayID: () -> Bool
        let updateImageCache: () async -> Void
        let sleep: (Duration) async -> Void
        let publishChange: () -> Void
        let invalidateMenuBarHeightCache: () -> Void
    }

    @MainActor
    static func execute(operations: Operations) async -> Outcome {
        operations.clearCacheLedger()
        operations.resetItemCache()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            operations.storeBackgroundContinuation(continuation)
            operations.startCacheRebuild()
        }
        operations.clearNewItemSuppression()

        operations.clearImageCache()
        operations.cleanupImageCache()

        let imageRefreshPath: ImageRefreshPath
        if operations.itemCacheHasDisplayID() {
            imageRefreshPath = .immediate
        } else {
            imageRefreshPath = .fallbackAfterCacheMiss
            await operations.sleep(MenuBarLayoutResetPolicy.delay(after: .cacheFallbackSettle))
        }
        await operations.updateImageCache()

        operations.publishChange()
        operations.invalidateMenuBarHeightCache()

        return Outcome(imageRefreshPath: imageRefreshPath)
    }
}
