//
//  MenuBarIdentityReconciler.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Reconciles newly observed source PIDs with the last stable cache cycle.
///
/// SourcePID resolution is intentionally heuristic: it matches CG menu-bar
/// windows to AX extras. During menu-bar moves AX geometry can lag behind CG
/// geometry, producing a plausible but wrong PID. When the same window ID was
/// previously associated with a stable PID, keep that identity rather than
/// letting a transient observation corrupt persisted layout identifiers.
enum MenuBarIdentityReconciler {
    struct Correction: Equatable {
        let windowID: CGWindowID
        let previousPID: pid_t
        let observedPID: pid_t
        let correctedNamespace: MenuBarItemTag.Namespace
    }

    struct Result: Equatable {
        let items: [MenuBarItem]
        let corrections: [Correction]

        var correctionCount: Int {
            corrections.count
        }
    }

    static func reconcile(
        items: [MenuBarItem],
        previousSourcePIDs: [CGWindowID: pid_t],
        bundleIdentifierForPID: (pid_t) -> String?
    ) -> Result {
        var reconciledItems = items
        var corrections = [Correction]()

        for index in reconciledItems.indices {
            let item = reconciledItems[index]
            guard !item.isControlItem,
                  let previousPID = previousSourcePIDs[item.windowID],
                  let observedPID = item.sourcePID,
                  observedPID != previousPID
            else {
                continue
            }

            let correctedNamespace: MenuBarItemTag.Namespace
            if let bundleIdentifier = bundleIdentifierForPID(previousPID) {
                correctedNamespace = .string(bundleIdentifier)
            } else {
                correctedNamespace = item.tag.namespace
            }

            let correctedTag = MenuBarItemTag(
                namespace: correctedNamespace,
                title: item.tag.title,
                windowID: item.windowID,
                instanceIndex: item.tag.instanceIndex
            )
            reconciledItems[index] = MenuBarItem(
                tag: correctedTag,
                windowID: item.windowID,
                ownerPID: item.ownerPID,
                sourcePID: previousPID,
                bounds: item.bounds,
                title: item.title,
                isOnScreen: item.isOnScreen
            )
            corrections.append(
                Correction(
                    windowID: item.windowID,
                    previousPID: previousPID,
                    observedPID: observedPID,
                    correctedNamespace: correctedNamespace
                )
            )
        }

        return Result(items: reconciledItems, corrections: corrections)
    }
}
