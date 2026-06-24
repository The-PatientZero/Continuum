//
//  MenuBarObservationFrame.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Normalized result of one WindowServer menu-bar observation.
///
/// The cache loop observes noisy windows: clone windows, stale window IDs, and
/// unresolved placeholders. Keeping this frame explicit lets the runtime decide
/// what is safe to pass to planning without mixing those rules into the manager.
struct MenuBarObservationFrame {
    let displayID: CGDirectDisplayID?
    let items: [MenuBarItem]
    let droppedCloneWindowIDs: Set<CGWindowID>
    let droppedCloneDescriptions: [String]
    let currentItemWindowIDs: [CGWindowID]?

    var cloneCount: Int {
        droppedCloneWindowIDs.count
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    var normalizedWindowIDs: [CGWindowID] {
        (currentItemWindowIDs ?? items.reversed().map(\.windowID))
            .filter { !droppedCloneWindowIDs.contains($0) }
    }

    init(
        displayID: CGDirectDisplayID?,
        items: [MenuBarItem],
        droppedCloneWindowIDs: Set<CGWindowID> = [],
        droppedCloneDescriptions: [String] = [],
        currentItemWindowIDs: [CGWindowID]? = nil
    ) {
        self.displayID = displayID
        self.items = items
        self.droppedCloneWindowIDs = droppedCloneWindowIDs
        self.droppedCloneDescriptions = droppedCloneDescriptions
        self.currentItemWindowIDs = currentItemWindowIDs
    }

    static func filteringSystemClones(
        displayID: CGDirectDisplayID?,
        rawItems: [MenuBarItem],
        currentItemWindowIDs: [CGWindowID]? = nil
    ) -> MenuBarObservationFrame {
        let cloneItems = rawItems.filter(\.isSystemClone)
        return MenuBarObservationFrame(
            displayID: displayID,
            items: rawItems.filter { !$0.isSystemClone },
            droppedCloneWindowIDs: Set(cloneItems.map(\.windowID)),
            droppedCloneDescriptions: cloneItems.map(\.tag.description),
            currentItemWindowIDs: currentItemWindowIDs
        )
    }

    func replacingItems(_ items: [MenuBarItem]) -> MenuBarObservationFrame {
        MenuBarObservationFrame(
            displayID: displayID,
            items: items,
            droppedCloneWindowIDs: droppedCloneWindowIDs,
            droppedCloneDescriptions: droppedCloneDescriptions,
            currentItemWindowIDs: currentItemWindowIDs
        )
    }

    func persistableIdentifiersForPreviouslySeenWindows(
        _ previousWindowIDs: [CGWindowID]
    ) -> Set<String> {
        let previousWindowIDSet = Set(previousWindowIDs)
        return Set(
            items
                .filter { previousWindowIDSet.contains($0.windowID) }
                .compactMap { MenuBarKnownItemIdentifierPolicy.persistableBaseIdentifier(for: $0) }
        )
    }
}
