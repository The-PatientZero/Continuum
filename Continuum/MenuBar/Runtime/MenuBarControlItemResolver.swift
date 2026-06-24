//
//  MenuBarControlItemResolver.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Resolves Continuum's control items from one live menu bar observation.
///
/// macOS can report these items with stale tags, missing titles, unreliable
/// source PIDs, or only recognizable geometry. Keeping the fallback chain here
/// gives the cache and layout runtimes one audited discovery path.
enum MenuBarControlItemResolver {
    static func resolve(
        items: inout [MenuBarItem],
        visibleControlItemWindowID: CGWindowID? = nil,
        hiddenControlItemWindowID: CGWindowID? = nil,
        alwaysHiddenControlItemWindowID: CGWindowID? = nil,
        processID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> MenuBarControlItems? {
        resolve(
            items: &items,
            windowIDs: MenuBarControlItemWindowIDs(
                visible: visibleControlItemWindowID,
                hidden: hiddenControlItemWindowID,
                alwaysHidden: alwaysHiddenControlItemWindowID
            ),
            processID: processID
        )
    }

    static func resolve(
        items: inout [MenuBarItem],
        windowIDs: MenuBarControlItemWindowIDs,
        processID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> MenuBarControlItems? {
        reclassifyKnownControlItem(
            in: &items,
            windowID: windowIDs.visible,
            tag: .visibleControlItem,
            title: ControlItem.Identifier.visible.rawValue,
            processID: processID
        )
        reclassifyKnownControlItem(
            in: &items,
            windowID: windowIDs.hidden,
            tag: .hiddenControlItem,
            title: ControlItem.Identifier.hidden.rawValue,
            processID: processID
        )
        reclassifyKnownControlItem(
            in: &items,
            windowID: windowIDs.alwaysHidden,
            tag: .alwaysHiddenControlItem,
            title: ControlItem.Identifier.alwaysHidden.rawValue,
            processID: processID
        )
        reclassifyVisibleControlItemFallback(in: &items, processID: processID)

        if let pair = resolveByTag(from: &items) {
            return pair
        }
        if let pair = resolveByProcessTitle(from: &items, processID: processID) {
            return pair
        }
        if let pair = resolveByWindowID(
            from: &items,
            hiddenControlItemWindowID: windowIDs.hidden,
            alwaysHiddenControlItemWindowID: windowIDs.alwaysHidden
        ) {
            return pair
        }
        return resolveByWideDividerGeometry(from: &items)
    }
}

private extension MenuBarControlItemResolver {
    static func resolveByTag(
        from items: inout [MenuBarItem]
    ) -> MenuBarControlItems? {
        guard let hidden = items.removeFirst(matching: .hiddenControlItem) else {
            return nil
        }
        return MenuBarControlItems(
            hidden: hidden,
            alwaysHidden: items.removeFirst(matching: .alwaysHiddenControlItem)
        )
    }

    static func resolveByProcessTitle(
        from items: inout [MenuBarItem],
        processID: pid_t
    ) -> MenuBarControlItems? {
        let hiddenTitle = ControlItem.Identifier.hidden.rawValue
        let alwaysHiddenTitle = ControlItem.Identifier.alwaysHidden.rawValue

        guard let hiddenIndex = items.firstIndex(where: {
            $0.sourcePID == processID && $0.title == hiddenTitle
        }) else {
            return nil
        }

        let hidden = items.remove(at: hiddenIndex)
        let alwaysHidden = items.firstIndex(where: {
            $0.sourcePID == processID && $0.title == alwaysHiddenTitle
        }).map {
            items.remove(at: $0)
        }
        return MenuBarControlItems(hidden: hidden, alwaysHidden: alwaysHidden)
    }

    static func resolveByWindowID(
        from items: inout [MenuBarItem],
        hiddenControlItemWindowID: CGWindowID?,
        alwaysHiddenControlItemWindowID: CGWindowID?
    ) -> MenuBarControlItems? {
        guard let hiddenControlItemWindowID,
              let hiddenIndex = items.firstIndex(where: { $0.windowID == hiddenControlItemWindowID })
        else {
            return nil
        }

        let hidden = items.remove(at: hiddenIndex)
        let alwaysHidden = alwaysHiddenControlItemWindowID.flatMap { windowID in
            items.firstIndex(where: { $0.windowID == windowID }).map {
                items.remove(at: $0)
            }
        }
        return MenuBarControlItems(hidden: hidden, alwaysHidden: alwaysHidden)
    }

    static func resolveByWideDividerGeometry(
        from items: inout [MenuBarItem]
    ) -> MenuBarControlItems? {
        let wideDividerIndices = MenuBarControlItemDiscoveryPolicy.wideDividerIndices(in: items)
        guard let hiddenIndex = wideDividerIndices.first else {
            return nil
        }

        let hidden = items.remove(at: hiddenIndex)
        let remainingAlwaysHiddenIndex = wideDividerIndices
            .dropFirst()
            .map {
                MenuBarControlItemDiscoveryPolicy.adjustedIndexAfterRemoving(
                    $0,
                    removedIndex: hiddenIndex
                )
            }
            .first
        let alwaysHidden = remainingAlwaysHiddenIndex.map {
            items.remove(at: $0)
        }
        return MenuBarControlItems(hidden: hidden, alwaysHidden: alwaysHidden)
    }

    static func reclassifyKnownControlItem(
        in items: inout [MenuBarItem],
        windowID: CGWindowID?,
        tag: MenuBarItemTag,
        title: String,
        processID: pid_t
    ) {
        guard let windowID,
              let index = items.firstIndex(where: { $0.windowID == windowID })
        else {
            return
        }

        let item = items[index]
        guard MenuBarControlItemDiscoveryPolicy.shouldReclassifyKnownControlItem(
            item,
            as: tag,
            title: title,
            processID: processID
        ) else {
            return
        }

        items[index] = MenuBarItem(
            tag: tag,
            windowID: item.windowID,
            ownerPID: item.ownerPID,
            sourcePID: processID,
            bounds: item.bounds,
            title: title,
            isOnScreen: item.isOnScreen
        )
    }

    static func reclassifyVisibleControlItemFallback(
        in items: inout [MenuBarItem],
        processID: pid_t
    ) {
        guard !items.contains(where: { $0.tag == .visibleControlItem }) else {
            return
        }

        guard let index = items.firstIndex(where: {
            MenuBarControlItemDiscoveryPolicy.isVisibleControlItemFallback($0)
        }) else {
            return
        }

        let item = items[index]
        items[index] = MenuBarItem(
            tag: .visibleControlItem,
            windowID: item.windowID,
            ownerPID: item.ownerPID,
            sourcePID: processID,
            bounds: item.bounds,
            title: ControlItem.Identifier.visible.rawValue,
            isOnScreen: item.isOnScreen
        )
    }
}
