//
//  MenuBarNotchBudgetPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure budget builder for notch-overflow saved-layout planning.
///
/// The manager owns live NSScreen and WindowServer reads. This policy owns the
/// geometry accounting that turns a volatile observation into deterministic
/// inputs for LayoutSolver.planNotchOverflow.
enum MenuBarNotchBudgetPolicy {
    struct ItemObservation: Equatable {
        let uniqueIdentifier: String
        let tag: MenuBarItemTag
        let bounds: CGRect
        let isLayoutItem: Bool
        let isTransientControlCenterItem: Bool
    }

    struct Budget: Equatable {
        let rightBoundary: CGFloat
        let availableWidth: CGFloat
        let visibleUIDs: [String]
        let uidWidths: [String: CGFloat]
        let nonLayoutCount: Int
        let nonLayoutFootprint: CGFloat
        let chevronFootprint: CGFloat
        let nonLayoutBreakdown: [String]
    }

    static let transientTags: [MenuBarItemTag] = [
        .audioVideoModule,
        .faceTime,
        .screenCaptureUI,
        .gameMode,
    ]

    static func buildBudget(
        items: [ItemObservation],
        desiredFiltered: [String],
        hiddenControlUID: String,
        visibleControlUID: String?,
        controlCenterBounds: CGRect?,
        screenMaxX: CGFloat,
        notchMaxX: CGFloat,
        notchGap: CGFloat
    ) -> Budget {
        let rightBoundary = controlCenterBounds?.minX ?? screenMaxX
        var availableWidth = rightBoundary - (notchMaxX + notchGap)
        let itemsByUID = Dictionary(
            items.map { ($0.uniqueIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let nonLayoutItems = items.filter { item in
            !item.isLayoutItem &&
                isInsideBudgetRange(item.bounds, notchMaxX: notchMaxX, rightBoundary: rightBoundary) &&
                !isTransientSystemItem(item)
        }
        let nonLayoutFootprint = nonLayoutItems.reduce(CGFloat(0)) { total, item in
            total + item.bounds.width
        }
        availableWidth -= nonLayoutFootprint

        let visibleUIDs = Array(desiredFiltered.prefix(while: { $0 != hiddenControlUID }))
        var uidWidths = [String: CGFloat]()
        for uid in visibleUIDs {
            guard let item = itemsByUID[uid], item.isLayoutItem else {
                continue
            }
            uidWidths[uid] = item.bounds.width
        }

        var chevronFootprint: CGFloat = 0
        if let visibleControlUID,
           let chevron = itemsByUID[visibleControlUID],
           isInsideBudgetRange(
               chevron.bounds,
               notchMaxX: notchMaxX,
               rightBoundary: rightBoundary
           )
        {
            chevronFootprint = chevron.bounds.width
            availableWidth -= chevronFootprint
        }

        return Budget(
            rightBoundary: rightBoundary,
            availableWidth: availableWidth,
            visibleUIDs: visibleUIDs,
            uidWidths: uidWidths,
            nonLayoutCount: nonLayoutItems.count,
            nonLayoutFootprint: nonLayoutFootprint,
            chevronFootprint: chevronFootprint,
            nonLayoutBreakdown: nonLayoutItems.map {
                "\($0.uniqueIdentifier)=\($0.bounds.width)"
            }
        )
    }

    private static func isInsideBudgetRange(
        _ bounds: CGRect,
        notchMaxX: CGFloat,
        rightBoundary: CGFloat
    ) -> Bool {
        bounds.minX >= notchMaxX && bounds.maxX <= rightBoundary
    }

    private static func isTransientSystemItem(_ item: ItemObservation) -> Bool {
        transientTags.contains { tag in
            tag.namespace == item.tag.namespace && tag.title == item.tag.title
        } || item.isTransientControlCenterItem
    }
}
