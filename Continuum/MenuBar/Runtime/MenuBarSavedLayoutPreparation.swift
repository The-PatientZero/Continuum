//
//  MenuBarSavedLayoutPreparation.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Builds the stable execution input for one saved-layout apply pass.
///
/// The manager owns live observations, settings, and movement. This value owns
/// the deterministic preparation step between an observation snapshot and the
/// runtime move executor: unmanaged item placement, notch overflow adjustment,
/// and execution-strategy selection.
enum MenuBarSavedLayoutPreparation {
    struct Settings: Equatable {
        let enableMenuBarItemOverflow: Bool
        let useLCSOnNotchedDisplay: Bool
    }

    struct ScreenObservation: Equatable {
        let frame: CGRect
        let hasNotch: Bool
        let notchFrame: CGRect?
    }

    struct NotchOverflow: Equatable {
        let budget: MenuBarNotchBudgetPolicy.Budget
        let result: LayoutSolver.NotchOverflowResult
    }

    struct Plan {
        let items: [MenuBarItem]
        let controlItems: MenuBarControlItems
        let sectionByWindowID: [CGWindowID: MenuBarSection.Name]
        let sectionUIDs: [MenuBarSection.Name: [String]]
        let currentFlat: [String]
        let desiredFiltered: [String]
        let sectionMap: [String: String]
        let hiddenControlUID: String
        let alwaysHiddenControlUID: String?
        let visibleControlUID: String?
        let unmanagedPlan: MenuBarUnmanagedPlacementPolicy.Plan
        let notchOverflow: NotchOverflow?
        let executionPlan: MenuBarSavedLayoutExecutionPolicy.InitialPlan
    }

    static func prepare(
        observationSnapshot: MenuBarSavedLayoutObservationSnapshot,
        savedSectionOrder: [String: [String]],
        newItemsPlacement: MenuBarNewItemsPlacement,
        settings: Settings,
        screen: ScreenObservation?,
        notchGap: CGFloat
    ) -> Plan {
        let items = observationSnapshot.items
        let controlItems = observationSnapshot.controlItems
        let hiddenControlUID = controlItems.hidden.uniqueIdentifier
        let alwaysHiddenControlUID = controlItems.alwaysHidden?.uniqueIdentifier
        let sequencePlan = observationSnapshot.sequencePlan

        let unmanagedPlan = MenuBarUnmanagedPlacementPolicy.plan(
            items: items.map { item in
                MenuBarUnmanagedPlacementPolicy.ItemObservation(
                    uniqueIdentifier: item.uniqueIdentifier,
                    tag: item.tag,
                    sourcePID: item.sourcePID
                )
            },
            currentFlat: sequencePlan.currentFlat,
            desiredFiltered: sequencePlan.desiredFiltered,
            sectionMap: sequencePlan.sectionMap,
            savedSectionOrder: savedSectionOrder,
            newItemsPlacement: newItemsPlacement,
            hiddenControlUID: hiddenControlUID,
            alwaysHiddenControlUID: alwaysHiddenControlUID
        )

        let notchAdjustment = notchOverflowAdjustment(
            items: items,
            desiredFiltered: unmanagedPlan.desiredFiltered,
            sectionMap: unmanagedPlan.sectionMap,
            unmanagedUIDs: unmanagedPlan.unmanagedUIDs,
            hiddenControlUID: hiddenControlUID,
            alwaysHiddenControlUID: alwaysHiddenControlUID,
            visibleControlUID: unmanagedPlan.visibleControlUID,
            settings: settings,
            screen: screen,
            notchGap: notchGap
        )
        let desiredFiltered = notchAdjustment?.result.updatedDesiredFiltered ??
            unmanagedPlan.desiredFiltered
        let sectionMap = notchAdjustment?.result.updatedSectionMap ??
            unmanagedPlan.sectionMap

        let executionStrategy = MenuBarSavedLayoutExecutionPolicy.strategy(
            displayHasNotch: screen?.hasNotch == true,
            useLCSOnNotchedDisplay: settings.useLCSOnNotchedDisplay
        )
        let executionPlan = MenuBarSavedLayoutExecutionPolicy.initialPlan(
            currentFlat: sequencePlan.currentFlat,
            desiredFiltered: desiredFiltered,
            sectionMap: sectionMap,
            hiddenControlUID: hiddenControlUID,
            alwaysHiddenControlUID: alwaysHiddenControlUID,
            strategy: executionStrategy
        )

        return Plan(
            items: items,
            controlItems: controlItems,
            sectionByWindowID: observationSnapshot.sectionByWindowID,
            sectionUIDs: sequencePlan.sectionUIDs,
            currentFlat: sequencePlan.currentFlat,
            desiredFiltered: desiredFiltered,
            sectionMap: sectionMap,
            hiddenControlUID: hiddenControlUID,
            alwaysHiddenControlUID: alwaysHiddenControlUID,
            visibleControlUID: unmanagedPlan.visibleControlUID,
            unmanagedPlan: unmanagedPlan,
            notchOverflow: notchAdjustment,
            executionPlan: executionPlan
        )
    }

    private static func notchOverflowAdjustment(
        items: [MenuBarItem],
        desiredFiltered: [String],
        sectionMap: [String: String],
        unmanagedUIDs: [String],
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?,
        visibleControlUID: String?,
        settings: Settings,
        screen: ScreenObservation?,
        notchGap: CGFloat
    ) -> NotchOverflow? {
        guard settings.enableMenuBarItemOverflow,
              let screen,
              screen.hasNotch,
              let notchFrame = screen.notchFrame
        else {
            return nil
        }

        let budget = MenuBarNotchBudgetPolicy.buildBudget(
            items: items.map { item in
                MenuBarNotchBudgetPolicy.ItemObservation(
                    uniqueIdentifier: item.uniqueIdentifier,
                    tag: item.tag,
                    bounds: item.bounds,
                    isLayoutItem: MenuBarSavedLayoutItemPolicy.isLayoutItem(item),
                    isTransientControlCenterItem: item.isTransientControlCenterItem
                )
            },
            desiredFiltered: desiredFiltered,
            hiddenControlUID: hiddenControlUID,
            visibleControlUID: visibleControlUID,
            controlCenterBounds: items.first(where: { $0.tag == .controlCenter })?.bounds,
            screenMaxX: screen.frame.maxX,
            notchMaxX: notchFrame.maxX,
            notchGap: notchGap
        )
        let result = LayoutSolver.planNotchOverflow(
            desiredFiltered: desiredFiltered,
            unmanagedUIDs: unmanagedUIDs,
            controlUIDs: ControlUIDs(
                visible: visibleControlUID,
                hidden: hiddenControlUID,
                alwaysHidden: alwaysHiddenControlUID
            ),
            sectionMap: sectionMap,
            uidWidths: budget.uidWidths,
            availableWidth: budget.availableWidth
        )
        return NotchOverflow(budget: budget, result: result)
    }
}
