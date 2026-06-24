//
//  MenuBarSectionTransitionExecutor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Executes the saved-layout hidden/always-hidden transition repair phase.
///
/// The primary repair moves the always-hidden divider once. A follow-up
/// classification pass then moves any items that still landed on the wrong side
/// of that divider, which keeps retries bounded when macOS reports transient
/// section assignments during menu-bar churn.
enum MenuBarSectionTransitionExecutor {
    enum StopReason: Equatable {
        case completed
        case cancelled
        case observationUnavailable
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
        plan: MenuBarSectionTransitionPolicy.AlwaysHiddenControlMovePlan,
        itemOrder: [String: [String]],
        hiddenControlUID: String,
        controlItemWindowIDs: MenuBarControlItemWindowIDs,
        observeItems: (String) async -> [MenuBarItem]?,
        makeSectionLookupContext: (MenuBarControlItems) -> MenuBarSectionLookupContext,
        moveItem: (MenuBarItem, MenuBarMoveDestination) async throws -> Void,
        recordControlMoveStart: (MenuBarMoveDestination) -> Void,
        recordControlMoveFailure: (Error) -> Void,
        recordFallbackPlan: (MenuBarSectionTransitionPolicy.FallbackPlan) -> Void,
        recordFallbackMoveFailure: (MenuBarSectionTransitionPolicy.FallbackMove, Error) -> Void,
        sleepAfterMove: (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> Outcome {
        var movedCount = 0

        guard let controlMoveItems = await observeItems("alwaysHiddenControlMove") else {
            return Outcome(movedCount: movedCount, stopReason: .observationUnavailable)
        }

        if let ahItem = controlMoveItems.first(where: { $0.uniqueIdentifier == plan.controlUID }) {
            let anchorUID = MenuBarSectionTransitionPolicy.resolvedAlwaysHiddenControlAnchorUID(
                for: plan,
                anchors: controlMoveItems.map { item in
                    MenuBarSectionTransitionPolicy.AnchorObservation(
                        uniqueIdentifier: item.uniqueIdentifier,
                        isMovable: item.isMovable
                    )
                },
                hiddenControlUID: hiddenControlUID
            )
            let destination = anchorUID.flatMap { anchorUID -> MenuBarMoveDestination? in
                guard let anchor = controlMoveItems.first(where: { $0.uniqueIdentifier == anchorUID }) else {
                    return nil
                }
                return .leftOfItem(anchor)
            }

            if let destination, !Task.isCancelled {
                recordControlMoveStart(destination)
                do {
                    try await moveItem(ahItem, destination)
                    movedCount += 1
                    await sleepAfterMove(MenuBarSavedLayoutExecutionPolicy.delay(after: .controlBoundaryMove))
                } catch {
                    recordControlMoveFailure(error)
                }
            }
        }

        guard let fallbackItems = await observeItems("crossSectionFallback") else {
            return Outcome(movedCount: movedCount, stopReason: .observationUnavailable)
        }
        var fallbackItemsCopy = fallbackItems
        guard let freshControl = MenuBarControlItems(
            items: &fallbackItemsCopy,
            windowIDs: controlItemWindowIDs
        ),
            let ahItem = fallbackItems.first(where: { $0.uniqueIdentifier == plan.controlUID })
        else {
            return Outcome(movedCount: movedCount, stopReason: .completed)
        }

        let verifyContext = makeSectionLookupContext(freshControl)
        let postSectionByWindowID = MenuBarSavedLayoutSequencePolicy.sectionSnapshot(
            items: fallbackItems,
            isLayoutItem: MenuBarSavedLayoutItemPolicy.isLayoutItem
        ) { item in
            verifyContext.findSection(for: item)
        }
        let postSectionSets = MenuBarSectionTransitionPolicy.sectionSets(
            observations: fallbackItems.map { item in
                MenuBarSectionTransitionPolicy.SectionObservation(
                    uniqueIdentifier: item.uniqueIdentifier,
                    windowID: item.windowID,
                    isLayoutItem: MenuBarSavedLayoutItemPolicy.isLayoutItem(item)
                )
            },
            sectionByWindowID: postSectionByWindowID,
            itemOrder: itemOrder
        )
        let fallbackPlan = MenuBarSectionTransitionPolicy.fallbackPlan(
            currentHidden: postSectionSets.currentHidden,
            currentAlwaysHidden: postSectionSets.currentAlwaysHidden,
            itemOrder: itemOrder
        )

        if fallbackPlan.hasMoves {
            recordFallbackPlan(fallbackPlan)
        }

        for fallbackMove in fallbackPlan.moves {
            guard !Task.isCancelled else {
                return Outcome(movedCount: movedCount, stopReason: .cancelled)
            }
            guard
                let item = fallbackItems.first(where: {
                    $0.uniqueIdentifier == fallbackMove.uniqueIdentifier &&
                        MenuBarSavedLayoutItemPolicy.isLayoutItem($0)
                })
            else {
                continue
            }

            let destination: MenuBarMoveDestination
            switch fallbackMove.destination {
            case .leftOfAlwaysHiddenControl:
                destination = .leftOfItem(ahItem)
            case .rightOfAlwaysHiddenControl:
                destination = .rightOfItem(ahItem)
            }

            do {
                try await moveItem(item, destination)
                movedCount += 1
                await sleepAfterMove(MenuBarSavedLayoutExecutionPolicy.delay(after: .crossSectionFallbackMove))
            } catch {
                recordFallbackMoveFailure(fallbackMove, error)
            }
        }

        return Outcome(movedCount: movedCount, stopReason: .completed)
    }
}
