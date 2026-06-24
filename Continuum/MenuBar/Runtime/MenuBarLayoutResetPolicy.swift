//
//  MenuBarLayoutResetPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure reset-planning rules for returning movable items to the hidden section.
///
/// The reset executor owns observation and move events. This policy owns which
/// items are eligible for reset moves and which refreshed items still need the
/// second pass after macOS has had time to settle the first pass.
enum MenuBarLayoutResetPolicy {
    enum Phase: Equatable {
        case controlRecoveryDisableSettle
        case controlRecoveryEnableSettle
        case firstPassSettle
        case cacheFallbackSettle
    }

    enum ControlRecoveryAction: Equatable {
        case toggleAlwaysHiddenSection
        case fail
    }

    static func delay(after phase: Phase) -> Duration {
        switch phase {
        case .controlRecoveryDisableSettle:
            .milliseconds(50)
        case .controlRecoveryEnableSettle:
            .milliseconds(150)
        case .firstPassSettle:
            .milliseconds(200)
        case .cacheFallbackSettle:
            .milliseconds(350)
        }
    }

    static func controlRecoveryAction(alwaysHiddenSectionEnabled: Bool) -> ControlRecoveryAction {
        alwaysHiddenSectionEnabled ? .toggleAlwaysHiddenSection : .fail
    }

    static func canMoveToHiddenDuringReset(_ item: MenuBarItem) -> Bool {
        item.tag != .visibleControlItem &&
            item.isMovable &&
            item.canBeHidden &&
            !item.isControlItem
    }

    static func moveCandidates(from items: [MenuBarItem]) -> [MenuBarItem] {
        items.filter(canMoveToHiddenDuringReset)
    }

    static func shouldRetryMoveToHidden(
        item: MenuBarItem,
        itemBounds: CGRect,
        hiddenControlBounds: CGRect,
        alwaysHiddenControlBounds: CGRect?
    ) -> Bool {
        guard canMoveToHiddenDuringReset(item) else {
            return false
        }

        if itemBounds.minX >= hiddenControlBounds.maxX {
            return true
        }
        if let alwaysHiddenControlBounds,
           itemBounds.maxX <= alwaysHiddenControlBounds.minX
        {
            return true
        }
        return false
    }

    static func secondPassCandidates(
        items: [MenuBarItem],
        hiddenControlBounds: CGRect,
        alwaysHiddenControlBounds: CGRect?,
        boundsForItem: (MenuBarItem) -> CGRect
    ) -> [MenuBarItem] {
        items.filter { item in
            shouldRetryMoveToHidden(
                item: item,
                itemBounds: boundsForItem(item),
                hiddenControlBounds: hiddenControlBounds,
                alwaysHiddenControlBounds: alwaysHiddenControlBounds
            )
        }
    }
}
