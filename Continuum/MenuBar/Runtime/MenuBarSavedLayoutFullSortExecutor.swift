//
//  MenuBarSavedLayoutFullSortExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Executes a saved-layout full-sort sequence against fresh menu-bar observations.
///
/// The full-sort path is used on notched displays where partial LCS moves can
/// leave stable anchors in the notch dead zone. Every UID is resolved against
/// the current WindowServer snapshot immediately before the move.
enum MenuBarSavedLayoutFullSortExecutor {
    enum StopReason: Equatable {
        case completed
        case cancelled
        case observationUnavailable
        case controlCenterMissing
    }

    struct Outcome: Equatable {
        let movedCount: Int
        let stopReason: StopReason

        var needsDeferredCacheRefresh: Bool {
            stopReason == .observationUnavailable
        }
    }

    @MainActor
    static func execute(
        sequence: [String],
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?,
        observationContext: String,
        observeItems: (String) async -> [MenuBarItem]?,
        moveItem: (MenuBarItem, MenuBarMoveDestination) async throws -> Void,
        recordItemMissing: (String) -> Void,
        recordControlCenterMissing: () -> Void,
        recordMoveStart: (String, MenuBarMoveDestination) -> Void,
        recordMoveFailure: (String, Error) -> Void,
        sleepAfterMove: (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> Outcome {
        var movedCount = 0

        for uid in sequence {
            guard !Task.isCancelled else {
                return Outcome(movedCount: movedCount, stopReason: .cancelled)
            }

            guard let freshItems = await observeItems(observationContext) else {
                return Outcome(movedCount: movedCount, stopReason: .observationUnavailable)
            }

            let resolution = MenuBarSavedLayoutExecutionPolicy.fullSortMoveResolution(
                uid: uid,
                items: freshItems,
                hiddenControlUID: hiddenControlUID,
                alwaysHiddenControlUID: alwaysHiddenControlUID,
                isLayoutItem: MenuBarSavedLayoutItemPolicy.isLayoutItem
            )

            let resolvedMove: MenuBarSavedLayoutExecutionPolicy.ResolvedMove
            switch resolution {
            case let .move(move):
                resolvedMove = move
            case .itemMissing:
                recordItemMissing(uid)
                continue
            case .controlCenterMissing:
                recordControlCenterMissing()
                return Outcome(movedCount: movedCount, stopReason: .controlCenterMissing)
            }

            recordMoveStart(uid, resolvedMove.destination)

            do {
                try await moveItem(resolvedMove.item, resolvedMove.destination)
                movedCount += 1
                await sleepAfterMove(MenuBarSavedLayoutExecutionPolicy.delay(after: .fullSortMove))
            } catch {
                recordMoveFailure(uid, error)
            }
        }

        return Outcome(movedCount: movedCount, stopReason: .completed)
    }
}
