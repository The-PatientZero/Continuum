//
//  MenuBarCachePopulationRuntime.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Builds the runtime item cache from one Window Server observation.
///
/// The manager supplies live bounds lookup and later publishes the cache. This
/// runtime owns the deterministic population pass so admission, sectioning,
/// temporary-reveal masking, and fallback accounting stay together.
enum MenuBarCachePopulationRuntime {
    struct Result: Equatable {
        let cache: MenuBarItemCache
        let validCount: Int
        let invalidCount: Int
        let duplicateItems: [MenuBarItem]
        let noSectionCount: Int
        let temporarilyShownCount: Int
        let missingSourcePIDItems: [MenuBarItem]
        let blockedNoSectionItems: [MenuBarItem]
        let hiddenFallbackItems: [MenuBarItem]
    }

    static func buildCache(
        items: [MenuBarItem],
        controlItems: MenuBarControlItems,
        displayID: CGDirectDisplayID?,
        temporaryContexts: [MenuBarCachePopulationPolicy.TemporaryContext],
        currentBoundsForItem: @escaping (MenuBarItem) -> CGRect?
    ) -> Result {
        var context = Context(
            controlItems: controlItems,
            displayID: displayID,
            currentBoundsForItem: currentBoundsForItem
        )
        var validCount = 0
        var invalidCount = 0
        var duplicateItems = [MenuBarItem]()
        var noSectionCount = 0
        var missingSourcePIDItems = [MenuBarItem]()
        var blockedNoSectionItems = [MenuBarItem]()
        var hiddenFallbackItems = [MenuBarItem]()
        var seenTags = Set<MenuBarItemTag>()

        for item in items {
            switch MenuBarCachePopulationPolicy.admissionDecision(for: item, seenTags: seenTags) {
            case .rejectUncacheable:
                invalidCount += 1
                continue
            case .rejectDuplicate:
                duplicateItems.append(item)
                continue
            case .admit:
                seenTags.insert(item.tag)
            }

            validCount += 1
            if item.sourcePID == nil {
                missingSourcePIDItems.append(item)
            }

            let section = context.findSection(for: item)

            if let temporaryDestination = MenuBarCachePopulationPolicy.temporaryDestination(
                for: item,
                currentSection: section,
                contexts: temporaryContexts
            ) {
                context.temporarilyShownItems.append((item, temporaryDestination))
                continue
            }

            if let section {
                context.cache[section].append(item)
                continue
            }

            noSectionCount += 1
            let currentBounds = currentBoundsForItem(item) ?? item.bounds
            switch MenuBarCachePopulationPolicy.noSectionFallback(for: currentBounds) {
            case .skipBlocked:
                blockedNoSectionItems.append(item)
            case .cacheInHidden:
                hiddenFallbackItems.append(item)
                context.cache[MenuBarSection.Name.hidden].append(item)
            }
        }

        for (item, destination) in context.temporarilyShownItems {
            context.cache.insert(item, at: destination)
        }

        return Result(
            cache: context.cache,
            validCount: validCount,
            invalidCount: invalidCount,
            duplicateItems: duplicateItems,
            noSectionCount: noSectionCount,
            temporarilyShownCount: context.temporarilyShownItems.count,
            missingSourcePIDItems: missingSourcePIDItems,
            blockedNoSectionItems: blockedNoSectionItems,
            hiddenFallbackItems: hiddenFallbackItems
        )
    }
}

private extension MenuBarCachePopulationRuntime {
    struct Context {
        var cache: MenuBarItemCache
        var temporarilyShownItems = [(MenuBarItem, MenuBarMoveDestination)]()

        private let sectionLookup: MenuBarSectionLookupContext
        private let currentBoundsForItem: (MenuBarItem) -> CGRect?

        init(
            controlItems: MenuBarControlItems,
            displayID: CGDirectDisplayID?,
            currentBoundsForItem: @escaping (MenuBarItem) -> CGRect?
        ) {
            self.cache = MenuBarItemCache(displayID: displayID)
            self.currentBoundsForItem = currentBoundsForItem
            self.sectionLookup = MenuBarSectionLookupContext(
                controlItems: controlItems,
                currentBoundsForItem: currentBoundsForItem
            )
        }

        func findSection(for item: MenuBarItem) -> MenuBarSection.Name? {
            sectionLookup.findSection(for: item)
        }
    }
}
