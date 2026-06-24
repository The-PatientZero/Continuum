//
//  MenuBarTemporaryRevealExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Executes one bounded temporary-reveal session.
///
/// The reveal policy owns snapshot-only decisions such as return-route capture,
/// anchor selection, existing-context admission, and move-error metadata. This
/// executor owns the runtime sequence around those decisions: forced rehide,
/// pending relocation persistence, HID pause/resume, reveal move, click
/// fallback, popup capture, context append, and rehide trigger scheduling.
enum MenuBarTemporaryRevealExecutor {
    private static let fastMoveAttemptBudget = 2
    private static let secondaryClickMoveAttemptBudget = 1
    private static let initialClickAttemptBudget = 1
    private static let fallbackClickAttemptBudget = 3

    struct Outcome: Equatable {
        let result: MenuBarTemporaryRevealResult
    }

    struct Operations {
        let hasTemporaryContexts: () -> Bool
        let cancelRehideTriggers: () -> Void
        let forceRehideExistingContexts: () async -> Void
        let outstandingContexts: () -> [MenuBarTemporaryRevealPolicy.OutstandingContext]
        let removeExistingContext: (MenuBarItemTag) -> Void
        let scheduleRehideTimer: () -> Void
        let observeItems: (CGDirectDisplayID) async -> [MenuBarItem]
        let showNoRoomAlert: (MenuBarItem) -> Void
        let recordPendingMetadata: (
            MenuBarTemporaryRevealPolicy.PendingMetadata,
            String
        ) -> Void
        let clearPendingRelocation: (String) -> Void
        let persistPendingRelocations: () -> Void
        let beginInputSession: () -> Void
        let endInputSession: () -> Void
        let windowOrigin: (CGWindowID) -> CGPoint?
        let moveItem: (
            MenuBarItem,
            MenuBarMoveDestination,
            CGDirectDisplayID,
            Int?
        ) async throws -> Void
        let appendContext: (MenuBarTemporaryRevealContext) -> Void
        let waitForItemToLeaveOrigin: (MenuBarItem, CGPoint, Duration) async -> Void
        let waitForItemPositionToSettle: (MenuBarItem) async -> Void
        let refreshedClickTarget: (MenuBarItem, CGDirectDisplayID) async -> MenuBarItem
        let sleep: (Duration) async -> Void
        let visibleWindowIDs: () -> Set<CGWindowID>
        let isElectronItem: (MenuBarItem) -> Bool
        let pressItemViaAccessibility: (MenuBarItem) -> Bool
        let clickItem: (MenuBarItem, CGMouseButton, Int) async throws -> Void
        let shownInterfaceWindow: (pid_t, Set<CGWindowID>) -> WindowInfo?
    }

    struct Diagnostics {
        var recordStart: (MenuBarItem) -> Void = { _ in }
        var recordAdmissionBlocked: ([MenuBarItemTag]) -> Void = { _ in }
        var recordMissingReturnDestination: (MenuBarItem, CGDirectDisplayID) -> Void = { _, _ in }
        var recordMissingRevealAnchor: (MenuBarItem) -> Void = { _ in }
        var recordRevealMoveStart: (MenuBarItem, CGDirectDisplayID) -> Void = { _, _ in }
        var recordMoveFailure: (MenuBarItem, Error) -> Void = { _, _ in }
        var recordPreservedPendingMetadata: (MenuBarItem, MenuBarSection.Name) -> Void = { _, _ in }
        var recordAccessibilityPressSuccess: (MenuBarItem) -> Void = { _ in }
        var recordInitialClickFailure: (MenuBarItem, Error) -> Void = { _, _ in }
        var recordFallbackClickFailure: (MenuBarItem, Error) -> Void = { _, _ in }
    }

    @MainActor
    static func execute(
        item: MenuBarItem,
        mouseButton: CGMouseButton,
        resolvedDisplayID: CGDirectDisplayID,
        originalSection: MenuBarSection.Name,
        fastPath: Bool,
        operations: Operations,
        diagnostics: Diagnostics = Diagnostics()
    ) async -> Outcome {
        diagnostics.recordStart(item)

        if mouseButton != .left, operations.hasTemporaryContexts() {
            diagnostics.recordAdmissionBlocked(
                operations.outstandingContexts().map(\.tag)
            )
            operations.scheduleRehideTimer()
            return Outcome(result: .showFailed)
        }

        if operations.hasTemporaryContexts() {
            operations.cancelRehideTriggers()
            await operations.forceRehideExistingContexts()

            let admission = MenuBarTemporaryRevealPolicy.admissionAfterForcedRehide(
                outstandingContexts: operations.outstandingContexts(),
                requestedTag: item.tag
            )
            switch admission {
            case let .block(stuckTags):
                diagnostics.recordAdmissionBlocked(stuckTags)
                operations.scheduleRehideTimer()
                return Outcome(result: .showFailed)
            case let .proceed(removeExistingMatchingContext):
                if removeExistingMatchingContext {
                    operations.removeExistingContext(item.tag)
                }
            }
        }

        let items = await operations.observeItems(resolvedDisplayID)
        guard let returnInfo = MenuBarTemporaryRevealPolicy.captureReturnInfo(
            for: item,
            in: items
        ) else {
            diagnostics.recordMissingReturnDestination(item, resolvedDisplayID)
            return Outcome(result: .showFailed)
        }

        guard let anchor = MenuBarTemporaryRevealPolicy.revealAnchor(for: item, in: items) else {
            diagnostics.recordMissingRevealAnchor(item)
            operations.showNoRoomAlert(item)
            return Outcome(result: .showFailed)
        }

        let moveDestination = MenuBarMoveDestination.leftOfItem(anchor)
        let returnRoute = MenuBarTemporaryRevealPolicy.ReturnRoute(
            destination: returnInfo.destination,
            fallbackNeighbor: returnInfo.fallbackNeighbor,
            originalSection: originalSection
        )
        let pendingMetadata = MenuBarTemporaryRevealPolicy.pendingMetadata(
            originalSection: originalSection,
            returnDestination: returnRoute.destination
        )
        let tagIdentifier = item.tag.tagIdentifier

        operations.recordPendingMetadata(pendingMetadata, tagIdentifier)
        operations.persistPendingRelocations()

        operations.beginInputSession()
        defer {
            operations.endInputSession()
        }

        diagnostics.recordRevealMoveStart(item, resolvedDisplayID)

        let preMoveOrigin = operations.windowOrigin(item.windowID)
        do {
            try await operations.moveItem(
                item,
                moveDestination,
                resolvedDisplayID,
                moveAttemptBudget(mouseButton: mouseButton, fastPath: fastPath)
            )
        } catch {
            diagnostics.recordMoveFailure(item, error)
            let currentOrigin = operations.windowOrigin(item.windowID)
            let metadataMutation = MenuBarTemporaryRevealPolicy
                .pendingMetadataMutationAfterMoveError(
                    preMoveOrigin: preMoveOrigin,
                    currentOrigin: currentOrigin,
                    metadata: pendingMetadata
                )

            switch metadataMutation {
            case let .preserve(metadata):
                diagnostics.recordPreservedPendingMetadata(item, originalSection)
                operations.recordPendingMetadata(metadata, tagIdentifier)
                operations.persistPendingRelocations()
            case .discard:
                operations.clearPendingRelocation(tagIdentifier)
                operations.persistPendingRelocations()
            }

            return Outcome(result: .showFailed)
        }

        let context = MenuBarTemporaryRevealContext(
            tag: item.tag,
            sourcePID: item.sourcePID ?? item.ownerPID,
            displayID: resolvedDisplayID,
            returnRoute: returnRoute
        )
        operations.appendContext(context)
        operations.cancelRehideTriggers()
        defer {
            operations.scheduleRehideTimer()
        }

        let clickTarget = await settledClickTarget(
            item: item,
            resolvedDisplayID: resolvedDisplayID,
            preMoveOrigin: preMoveOrigin,
            fastPath: fastPath,
            operations: operations
        )
        let idsBeforeClick = operations.visibleWindowIDs()
        let clickPID = clickTarget.sourcePID ?? clickTarget.ownerPID

        if MenuBarClickTargetPolicy.shouldAttemptAccessibilityPress(
            mouseButton: mouseButton,
            isElectronItem: operations.isElectronItem(clickTarget)
        ), operations.pressItemViaAccessibility(clickTarget) {
            diagnostics.recordAccessibilityPressSuccess(clickTarget)
        } else {
            do {
                try await operations.clickItem(
                    clickTarget,
                    mouseButton,
                    initialClickAttemptBudget
                )
            } catch {
                diagnostics.recordInitialClickFailure(clickTarget, error)
                let fallbackItem = await operations.refreshedClickTarget(
                    clickTarget,
                    resolvedDisplayID
                )

                do {
                    try await operations.clickItem(
                        fallbackItem,
                        mouseButton,
                        fallbackClickAttemptBudget
                    )
                } catch {
                    diagnostics.recordFallbackClickFailure(item, error)
                    return Outcome(result: .movedButClickFailed)
                }
            }
        }

        await operations.sleep(MenuBarEventPacingPolicy.popupCaptureDelay)
        context.shownInterfaceWindow = operations.shownInterfaceWindow(
            clickPID,
            idsBeforeClick
        )

        return Outcome(result: .movedAndClicked)
    }

    @MainActor
    private static func settledClickTarget(
        item: MenuBarItem,
        resolvedDisplayID: CGDirectDisplayID,
        preMoveOrigin: CGPoint?,
        fastPath: Bool,
        operations: Operations
    ) async -> MenuBarItem {
        if fastPath {
            if let preMoveOrigin {
                await operations.waitForItemToLeaveOrigin(
                    item,
                    preMoveOrigin,
                    MenuBarEventPacingPolicy.revealedItemFastSettleTimeout
                )
            }
            return await operations.refreshedClickTarget(item, resolvedDisplayID)
        }

        await operations.waitForItemPositionToSettle(item)
        let clickTarget = await operations.refreshedClickTarget(item, resolvedDisplayID)
        await operations.sleep(MenuBarEventPacingPolicy.revealedItemPostMoveProcessingDelay)
        return clickTarget
    }

    private static func moveAttemptBudget(
        mouseButton: CGMouseButton,
        fastPath: Bool
    ) -> Int? {
        guard mouseButton == .left else {
            return secondaryClickMoveAttemptBudget
        }
        return fastPath ? fastMoveAttemptBudget : nil
    }
}
