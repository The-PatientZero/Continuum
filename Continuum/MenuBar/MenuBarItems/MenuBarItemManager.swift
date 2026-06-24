//
//  MenuBarItemManager.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@preconcurrency import AXSwift
import Cocoa
@preconcurrency import Combine
@preconcurrency import CoreGraphics

/// Manager for menu bar items.
@MainActor
final class MenuBarItemManager: ObservableObject {
    static let layoutWatchdogTimeout: DispatchTimeInterval = .seconds(6)

    /// Delay between relocation/restore moves and the subsequent recache,
    /// giving macOS time to settle menu bar item positions.
    static let uiSettleDelay: Duration = .milliseconds(300)

    /// The current cache of menu bar items.
    @Published private(set) var itemCache = MenuBarItemCache(displayID: nil)

    /// Compact runtime health model for diagnostics and control-plane reads.
    @Published private var diagnosticsRuntime = MenuBarDiagnosticsRuntime()

    /// Current diagnostics snapshot for observers and control-plane reads.
    var runtimeDiagnostics: MenuBarRuntimeDiagnostics {
        diagnosticsRuntime.diagnostics
    }

    /// The current high-level runtime state.
    var runtimeState: MenuBarRuntimeState {
        diagnosticsRuntime.state
    }

    /// The most recent immutable snapshot produced by the runtime.
    var latestRuntimeSnapshot: MenuBarSnapshot? {
        diagnosticsRuntime.lastSnapshot
    }

    /// A Boolean value that indicates whether the control items for the
    /// hidden sections are missing from the menu bar.
    var areControlItemsMissing: Bool {
        diagnosticsRuntime.areControlItemsMissing
    }

    /// Diagnostic logger for the menu bar item manager.
    fileprivate static nonisolated let diagLog = DiagLog(category: "MenuBarItemManager")

    /// Cache admission, baseline, and deferred-recache lifecycle state.
    private var cacheRuntime = MenuBarCacheCycleRuntime()

    /// Coalesces delayed cache refreshes after saved-layout mutations.
    private var deferredCacheRefreshRuntime = MenuBarDeferredCacheRefreshRuntime()

    /// Serial lane for notification/timer-triggered cache refreshes.
    private var eventRefreshRuntime = MenuBarEventRefreshRuntime()

    /// Live context and trigger state for temporarily revealed items.
    private nonisolated(unsafe) var temporaryRevealRuntime = MenuBarTemporaryRevealRuntime()

    /// Lightweight pacing, timeout, cursor, and gate state for CGEvent operations.
    private var syntheticEventRuntime = MenuBarSyntheticEventRuntime()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Shared state for the expensive menu-open probe used by smart rehide.
    private var menuOpenProbeRuntime = MenuBarMenuOpenProbeRuntime()

    /// Timer for lightweight periodic cache checks.
    private nonisolated(unsafe) var cacheTickCancellable: AnyCancellable?

    /// Persisted identity and first-run suppression state for observed items.
    private var knownItemLedger = MenuBarKnownItemLedger()

    deinit {
        temporaryRevealRuntime.cancelAll()
        deferredCacheRefreshRuntime.cancel()
        eventRefreshRuntime.cancel()
        cacheRuntime.cancelFollowUpRecache()
        cacheTickCancellable?.cancel()
        menuOpenProbeRuntime.cancel()
        startupSettlingRuntime.cancelAll()
    }

    // MARK: - Layout coordination state

    //
    // The flags below coordinate three overlapping concerns. They are
    // not collapsed into a single token because the AX-timing and live-
    // Window-Server interactions each one guards have evolved
    // independently from production incidents. Any consolidation needs
    // manual smoke-testing on real hardware to catch regressions that
    // unit tests cannot.
    //
    // 1. In-flight gating of the cache cycle. While one of these is
    //    set, cacheItemsRegardless suppresses restore, late-arrival
    //    detection, or section-order saves so an in-flight operation
    //    isn't fought by the cycle:
    //      - layoutMutationState reset / restore scopes
    //      - knownItemLedger relocation suppression
    //
    // 2. Startup settling. Gates restore and saves during the cold-boot
    //    or post-permission-grant window when many apps appear at once:
    //      - startupSettlingRuntime
    //
    /// Layout-wide mutation state that suppresses unsafe cache persistence.
    private var layoutMutationState = MenuBarLayoutMutationState()
    /// Shared state for startup/app-restart settling and initial cache warm-up.
    private var startupSettlingRuntime = MenuBarStartupSettlingRuntime()

    /// Persisted recovery state for temporarily shown items that still need to return.
    private var pendingRelocationLedger = PendingRelocationLedger()

    /// Persisted per-section item order and save/prune transitions.
    private var savedSectionOrderLedger = MenuBarSavedSectionOrderLedger()

    /// Persisted per-section item order. Maps section key to an ordered list of
    /// `uniqueIdentifier` strings (right-to-left, matching cache array order).
    private var savedSectionOrder: [String: [String]] {
        get { savedSectionOrderLedger.order }
        set { savedSectionOrderLedger.replace(with: newValue) }
    }
    /// Placement preference for newly detected menu bar items.
    @Published private(set) var newItemsPlacement = MenuBarNewItemsPlacement.defaultValue

    /// Loads persisted known item identifiers.
    private func loadKnownItemIdentifiers() {
        let defaults = UserDefaults.standard
        if let stored = defaults.array(forKey: MenuBarKnownItemLedger.defaultsKey) as? [String] {
            knownItemLedger.load(stored)
        }
    }

    /// Persists known item identifiers.
    private func persistKnownItemIdentifiers() {
        let defaults = UserDefaults.standard
        defaults.set(
            knownItemLedger.persistenceSnapshot,
            forKey: MenuBarKnownItemLedger.defaultsKey
        )
    }

    /// Loads persisted pending relocations for temporarily shown items
    /// whose apps quit before they could be rehidden.
    private func loadPendingRelocations() {
        let relocations = UserDefaults.standard.dictionary(
            forKey: PendingRelocationLedger.relocationsDefaultsKey
        ) as? [String: String] ?? [:]
        let returnDestinations = UserDefaults.standard.dictionary(
            forKey: PendingRelocationLedger.returnDestinationsDefaultsKey
        ) as? [String: [String: String]] ?? [:]
        pendingRelocationLedger.load(
            relocations: relocations,
            returnDestinations: returnDestinations
        )
    }

    /// Persists pending relocations.
    private func persistPendingRelocations() {
        UserDefaults.standard.set(
            pendingRelocationLedger.relocations,
            forKey: PendingRelocationLedger.relocationsDefaultsKey
        )
        UserDefaults.standard.set(
            pendingRelocationLedger.returnDestinations,
            forKey: PendingRelocationLedger.returnDestinationsDefaultsKey
        )
    }

    /// Loads persisted section order.
    private func loadSavedSectionOrder() {
        if let stored = UserDefaults.standard.dictionary(
            forKey: MenuBarSavedSectionOrderLedger.defaultsKey
        ) as? [String: [String]] {
            savedSectionOrderLedger.load(stored)
        }
    }

    /// Loads the persisted placement preference for newly detected menu bar items.
    private func loadNewItemsPlacementPreference() {
        newItemsPlacement = MenuBarNewItemsPlacementPreference.load(
            encodedData: Defaults.data(forKey: .newItemsPlacementData),
            legacySectionKey: Defaults.string(forKey: .newItemsSection)
        )
    }

    /// Persists the placement preference for newly detected menu bar items.
    private func persistNewItemsPlacementPreference() {
        Defaults.set(newItemsPlacement.sectionKey, forKey: .newItemsSection)
        if let data = MenuBarNewItemsPlacementPreference.encodedData(for: newItemsPlacement) {
            Defaults.set(data, forKey: .newItemsPlacementData)
        } else {
            Defaults.removeObject(forKey: .newItemsPlacementData)
        }
    }

    /// Persists the current saved section order.
    private func persistSavedSectionOrder() {
        UserDefaults.standard.set(
            savedSectionOrderLedger.persistenceSnapshot,
            forKey: MenuBarSavedSectionOrderLedger.defaultsKey
        )
    }

    /// Returns the current layout in a shape the Settings UI can stage
    /// without touching live menu bar positions.
    func layoutEditorSnapshot() -> MenuBarLayoutEditorSnapshot {
        let fallbackSectionOrder = savedSectionOrder.isEmpty
            ? computeSectionOrder(from: itemCache)
            : savedSectionOrder
        return MenuBarLayoutEditorPolicy.snapshot(
            cache: itemCache,
            savedSectionOrder: savedSectionOrder,
            fallbackSectionOrder: fallbackSectionOrder
        )
    }

    /// Refreshes the cache for the layout editor with source PID resolution.
    /// This is intentionally read-side only for Settings: it must not apply a
    /// saved layout while the user is merely opening the editor.
    func refreshLayoutEditorCache() async {
        await cacheItemsRegardless(
            skipRecentMoveCheck: true,
            resolveSourcePID: true,
            skipSavedLayoutApply: true
        )
    }

    /// Persists a staged Settings layout and applies it once through the same
    /// bulk reconciliation path used after app restarts.
    func applyLayoutEditorOrder(_ order: [MenuBarSection.Name: [String]]) async {
        let persistedOrder = MenuBarSavedOrderPolicy.sanitizedLayoutEditorOrder(order)

        savedSectionOrderLedger.replace(with: persistedOrder)
        persistSavedSectionOrder()

        if let alwaysHiddenItems = persistedOrder[sectionKey(for: .alwaysHidden)],
           !alwaysHiddenItems.isEmpty,
           appState?.settings.advanced.enableAlwaysHiddenSection != true
        {
            appState?.settings.advanced.enableAlwaysHiddenSection = true
            try? await Task.sleep(for: .milliseconds(150))
        }

        var itemSectionMap = [String: String]()
        for (sectionKey, identifiers) in persistedOrder {
            for identifier in identifiers {
                itemSectionMap[identifier] = sectionKey
            }
        }

        await applySavedSectionLayout(
            itemSectionMap: itemSectionMap,
            itemOrder: persistedOrder
        )
    }

    /// Extracts the current per-section item order from the given cache and
    /// persists it. Skips the write when the order has not changed.
    /// For items currently in the cache, uses their current section.
    /// For items from apps that are closed (not in cache), preserves their saved section.
    /// Computes the per-section item order dict from the given cache
    /// using the same filter and closed-app preservation logic that
    /// saveSectionOrder applies before persisting. Returns the dict
    /// without writing it anywhere.
    ///
    /// Exposed (rather than inlined inside saveSectionOrder) so layout
    /// restore and tests build their ordered section maps through the same
    /// filtering pipeline.
    ///
    /// Filter and merge:
    ///   - control items are excluded except the visibleControlItem
    ///     (Continuum chevron); its position within the visible section is
    ///     persisted so the LCS planner can detect when macOS placed
    ///     an app item on the wrong side of the chevron;
    ///   - non-control items without stable identity confidence are
    ///     excluded (their UIDs are unstable and would churn entries
    ///     every cycle);
    ///   - transient Control Center items (Live Activities, iPhone
    ///     Mirroring, generic Apple Item-0 placeholders) are excluded
    ///     so their ephemeral identifiers never enter the dict;
    ///   - items whose true section is recorded in
    ///     pendingReturnDestinations / pendingRelocations are treated
    ///     as closed-apps (preserves their pre-temporarilyShow section
    ///     instead of capturing the live visible position);
    ///   - LayoutSolver.planSectionOrder merges currentInSection with
    ///     closed-app entries from the previous savedSectionOrder so an
    ///     app's slot survives a quit / restart cycle.
    func computeSectionOrder(from cache: MenuBarItemCache) -> [String: [String]] {
        MenuBarSavedOrderPolicy.build(
            from: cache,
            previousSavedSectionOrder: savedSectionOrder,
            pendingReturnDestinations: pendingRelocationLedger.returnDestinations,
            pendingRelocations: pendingRelocationLedger.relocations
        )
    }

    /// Extracts the current per-section item order from the given cache
    /// and persists it to savedSectionOrder. Skips the write when the
    /// order has not changed. Delegates the dict construction to
    /// computeSectionOrder so the "what does the curated section order
    /// look like?" question has a single answer used by both periodic
    /// save path.
    private func saveSectionOrder(from cache: MenuBarItemCache) {
        let newOrder = computeSectionOrder(from: cache)
        guard savedSectionOrderLedger.replaceIfChanged(with: newOrder) else { return }
        persistSavedSectionOrder()
        MenuBarItemManager.diagLog.debug("Saved section order: \(newOrder.mapValues(\.count))")
    }

    /// Returns a persistable string key for the given section name.
    private func sectionKey(for section: MenuBarSection.Name) -> String {
        switch section {
        case .visible: "visible"
        case .hidden: "hidden"
        case .alwaysHidden: "alwaysHidden"
        }
    }

    /// Returns the section name for the given persisted key, if valid.
    private func sectionName(for key: String) -> MenuBarSection.Name? {
        switch key {
        case "visible": .visible
        case "hidden": .hidden
        case "alwaysHidden": .alwaysHidden
        default: nil
        }
    }

    /// Returns the effective section for newly detected menu bar items, falling back
    /// to hidden when the always-hidden section is currently disabled.
    var effectiveNewItemsSection: MenuBarSection.Name {
        MenuBarNewItemsPlacementPolicy.effectiveSection(
            placement: newItemsPlacement,
            alwaysHiddenEnabled: appState?.settings.advanced.enableAlwaysHiddenSection == true
        )
    }

    /// Returns the insertion index for the New Items badge within the given section.
    func newItemsBadgeIndex(in section: MenuBarSection.Name, itemIdentifiers: [String]) -> Int? {
        MenuBarNewItemsPlacementPolicy.badgeIndex(
            in: section,
            itemIdentifiers: itemIdentifiers,
            placement: newItemsPlacement,
            savedSectionOrder: savedSectionOrder,
            alwaysHiddenEnabled: appState?.settings.advanced.enableAlwaysHiddenSection == true
        )
    }

    /// Updates the preferred destination for newly detected menu bar items using the
    /// badge position from the layout editor.
    func updateNewItemsPlacement(
        section: MenuBarSection.Name,
        arrangedViews: [LayoutBarArrangedView]
    ) {
        let arrangedElements = arrangedViews.map { view in
            switch view.kind {
            case let .item(item):
                MenuBarNewItemsPlacementPolicy.ArrangedElement.item(identifier: item.uniqueIdentifier)
            case .newItemsBadge:
                MenuBarNewItemsPlacementPolicy.ArrangedElement.newItemsBadge
            }
        }
        let updatedPlacement = MenuBarNewItemsPlacementPolicy.updatedPlacement(
            for: section,
            arrangedElements: arrangedElements,
            alwaysHiddenEnabled: appState?.settings.advanced.enableAlwaysHiddenSection == true
        )

        guard newItemsPlacement != updatedPlacement else {
            return
        }

        newItemsPlacement = updatedPlacement
        persistNewItemsPlacementPreference()
        let resolvedSection = MenuBarNewItemsPlacementPolicy.sectionName(for: updatedPlacement.sectionKey) ?? .hidden
        MenuBarItemManager.diagLog.debug("Updated new item destination to \(resolvedSection.logString) at relation \(updatedPlacement.relation.rawValue)")
    }

    /// Applies a previously captured ``MenuBarNewItemsPlacement``,
    /// clamping to the hidden section when the always-hidden section is
    /// disabled. Persists the updated preference.
    ///
    /// When clamping from `alwaysHidden` to `hidden`, the original anchor
    /// references an alwaysHidden item that won't resolve in the hidden
    /// section. Rather than letting the badge fall through to the
    /// `.hidden`/always-hidden-disabled default (which is the leftmost
    /// slot, farthest from the clock), we re-anchor to the rightmost
    /// existing hidden item with `.leftOfAnchor` so the badge lands on
    /// the clock-side edge of the section; the spot users reach first
    /// when they expand the hidden section.
    func applyNewItemsPlacement(_ placement: MenuBarNewItemsPlacement) {
        let hiddenItems = itemCache[.hidden].map {
            MenuBarNewItemsPlacementPolicy.AnchorCandidate(
                identifier: $0.uniqueIdentifier,
                isControlItem: $0.isControlItem,
                instanceIndex: $0.tag.instanceIndex
            )
        }
        let adjusted = MenuBarNewItemsPlacementPolicy.appliedPlacement(
            placement,
            hiddenItems: hiddenItems,
            alwaysHiddenEnabled: appState?.settings.advanced.enableAlwaysHiddenSection == true
        )

        guard newItemsPlacement != adjusted else { return }

        newItemsPlacement = adjusted
        persistNewItemsPlacementPreference()
        let resolvedSection = MenuBarNewItemsPlacementPolicy.sectionName(for: adjusted.sectionKey) ?? .hidden
        MenuBarItemManager.diagLog.debug("Applied new item destination to \(resolvedSection.logString) at relation \(adjusted.relation.rawValue)")
    }

    /// Returns the move destination that inserts a new item into the preferred section.
    private func newItemsMoveDestination(
        for controlItems: MenuBarControlItems,
        among items: [MenuBarItem]
    ) -> MenuBarMoveDestination {
        let targetSection = effectiveNewItemsSection
        let context = sectionLookupContext(for: controlItems)
        let activelyShownTags = temporaryRevealRuntime.activeTagIdentifiers
        let liveSectionItems = items.filter { item in
            guard !item.isControlItem else { return false }
            guard !activelyShownTags.contains(item.tag.tagIdentifier) else { return false }
            return context.findSection(for: item) == targetSection
        }

        let intent = MenuBarNewItemsPlacementPolicy.moveDestinationIntent(
            placement: newItemsPlacement,
            liveSectionItemIdentifiers: liveSectionItems.map(\.uniqueIdentifier),
            targetSection: targetSection,
            alwaysHiddenEnabled: appState?.settings.advanced.enableAlwaysHiddenSection == true,
            hasAlwaysHiddenControl: controlItems.alwaysHidden != nil
        )

        func controlItem(for anchor: MenuBarNewItemsPlacementPolicy.ControlAnchor) -> MenuBarItem {
            switch anchor {
            case .hidden:
                return controlItems.hidden
            case .alwaysHidden:
                return controlItems.alwaysHidden ?? controlItems.hidden
            }
        }

        switch intent {
        case let .leftOfIdentifier(identifier):
            let anchorItem = liveSectionItems.first { $0.uniqueIdentifier == identifier } ?? controlItems.hidden
            return .leftOfItem(anchorItem)
        case let .rightOfIdentifier(identifier):
            let anchorItem = liveSectionItems.first { $0.uniqueIdentifier == identifier } ?? controlItems.hidden
            return .rightOfItem(anchorItem)
        case let .leftOfControl(anchor):
            return .leftOfItem(controlItem(for: anchor))
        case let .rightOfControl(anchor):
            return .rightOfItem(controlItem(for: anchor))
        }
    }

    private(set) weak var appState: AppState?

    /// Sets up the manager.
    func performSetup(with appState: AppState) async {
        MenuBarItemManager.diagLog.debug("performSetup: starting MenuBarItemManager setup")
        self.appState = appState
        loadKnownItemIdentifiers()
        loadPendingRelocations()
        loadSavedSectionOrder()
        loadNewItemsPlacementPreference()
        MenuBarItemManager.diagLog.debug("performSetup: loaded \(knownItemLedger.count) known identifiers, \(savedSectionOrder.values.map(\.count)) saved order entries")
        // On first launch (no known identifiers), avoid auto-relocating the leftmost item
        // so everything remains in the hidden section until the user interacts.
        knownItemLedger.armFirstLaunchSuppressionIfEmpty()
        configureCancellables(with: appState)
        startupSettlingRuntime.cancelInitialCacheTask()
        MenuBarItemManager.diagLog.debug("performSetup: scheduling initial cacheItemsRegardless off the startup critical path")
        let initialCacheTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await MenuBarInitialCacheExecutor.execute(
                operations: MenuBarInitialCacheExecutor.Operations(
                    runFastCache: {
                        await self.cacheItemsRegardless(resolveSourcePID: false)
                        return self.itemCache.displayID != nil
                    },
                    scheduleAuthoritativeRefresh: {
                        self.scheduleEventRefresh(.fullRefresh())
                    },
                    sleepBeforeRetry: {
                        try await Task.sleep(
                            for: MenuBarRuntimeRefreshPolicy.initialCacheRetryDelay
                        )
                    }
                ),
                diagnostics: MenuBarInitialCacheExecutor.Diagnostics(
                    recordStart: {
                        MenuBarItemManager.diagLog.debug(
                            "performSetup: initial cacheItemsRegardless started (fast path without sourcePID resolution)"
                        )
                    },
                    recordRetryNeeded: { attempt in
                        MenuBarItemManager.diagLog.debug(
                            "performSetup: fast initial cache missing control items on attempt \(attempt), retrying shortly"
                        )
                    },
                    recordRetrySuccess: { attempt in
                        MenuBarItemManager.diagLog.debug(
                            "performSetup: fast initial cache succeeded on retry \(attempt)"
                        )
                    }
                )
            )
            switch outcome {
            case .completed:
                MenuBarItemManager.diagLog.debug("performSetup: initial cache complete, items in cache: visible=\(itemCache[.visible].count), hidden=\(itemCache[.hidden].count), alwaysHidden=\(itemCache[.alwaysHidden].count), managedItems=\(itemCache.managedItems.count)")
            case .cancelled:
                return
            }
        }
        startupSettlingRuntime.attachInitialCacheTask(initialCacheTask)
        // Suppress restore and section-order saves for a settling period after launch.
        // During login (system uptime < 60 s) many apps load over ~30 s, each triggering
        // a cache cycle; without this guard every launch notification causes a restore
        // that conflicts with the next, producing the "icon parade" effect.
        // After the settling period ends, one final cacheItemsRegardless() enforces the
        // user's saved layout against whatever macOS placed items.
        startSettlingPeriod(reason: "performSetup")
        MenuBarItemManager.diagLog.debug("performSetup: MenuBarItemManager setup complete")
    }

    /// Starts a settling period during which restore and section-order saves
    /// are suppressed. The settling task polls cacheItemsRegardless until
    /// the menu bar has stabilized; then runs two final cache passes that
    /// trigger the saved-layout restore.
    ///
    /// Exit conditions, in priority order:
    /// 1. If expectedBundleIDs is non-empty: exit when all expected bundle
    ///    IDs are present in the cache AND sourcePIDs have resolved (≤1 nil).
    ///    This is the tracked app-restart case where we know exactly which
    ///    apps we're waiting on.
    /// 2. Otherwise: exit when the managed-item count has been stable for
    ///    stableTarget consecutive polls AND sourcePIDs have resolved.
    ///    This is the cold-start case where we don't know the expected set.
    /// 3. Hard upper bound is maxDuration from now. Sized generously
    ///    because some apps can take tens of seconds between process
    ///    respawn and menu bar item reattachment; the early-exit in (1)
    ///    or (2) ends settling immediately once the cache has caught up,
    ///    so the cap only matters when an app is genuinely slow or dead.
    ///
    /// On re-entry (for example, a permission re-grant during login), take
    /// the MAX of the previous deadline and the newly computed one so a
    /// second call does not silently truncate an in-flight window.
    func startSettlingPeriod(
        reason: String,
        expectedBundleIDs: Set<String> = [],
        maxDuration: Duration = .seconds(60)
    ) {
        let startDecision = startupSettlingRuntime.planStart(
            reason: reason,
            incomingExpectedBundleIDs: expectedBundleIDs,
            maxDuration: maxDuration
        )
        let configuration: MenuBarStartupSettlingPolicy.StartConfiguration
        switch startDecision {
        case let .ignore(kindDescription):
            MenuBarItemManager.diagLog.debug(
                "\(reason): settling start ignored; \(kindDescription) settling already in flight"
            )
            return
        case let .start(startConfiguration):
            configuration = startConfiguration
        }

        MenuBarItemManager.diagLog.debug("\(reason): settling period started (max duration: \(maxDuration))")
        // @MainActor ensures the flag flip and final cache call are never
        // interleaved with notification-triggered cache cycles between them.
        let initialCacheTask = startupSettlingRuntime.currentInitialCacheTask
        let settlingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await MenuBarStartupSettlingExecutor.execute(
                configuration: configuration,
                operations: MenuBarStartupSettlingExecutor.Operations(
                    waitForInitialCache: { await initialCacheTask?.value },
                    pollCache: { await self.startupSettlingObservation() },
                    finishSettlingWindow: { self.startupSettlingRuntime.finishSettling() },
                    runFastRestore: {
                        await self.cacheItemsRegardless(
                            skipRecentMoveCheck: true,
                            resolveSourcePID: false
                        )
                    },
                    runAuthoritativeRestore: {
                        await self.cacheItemsRegardless(
                            skipRecentMoveCheck: true,
                            resolveSourcePID: true
                        )
                    },
                    sleepBetweenPolls: {
                        try await Task.sleep(for: .milliseconds(500), tolerance: .milliseconds(100))
                    },
                    now: { ContinuousClock.now }
                ),
                diagnostics: self.startupSettlingDiagnostics(reason: reason)
            )
            if outcome == .cancelled {
                return
            }
        }
        startupSettlingRuntime.attachSettlingTask(settlingTask)
    }

    private func startupSettlingObservation() async -> MenuBarStartupSettlingExecutor.Observation {
        await cacheItemsRegardless(skipRecentMoveCheck: true, resolveSourcePID: true)

        let managedItems = itemCache.managedItems
        let presentBundleIDs = Set(
            managedItems.compactMap { item in
                if case let .string(bundleID) = item.tag.namespace {
                    return bundleID
                }
                return nil
            }
        )

        return MenuBarStartupSettlingExecutor.Observation(
            managedItemCount: managedItems.count,
            unresolvedSourcePIDCount: managedItems.count(where: { $0.sourcePID == nil }),
            presentBundleIDs: presentBundleIDs
        )
    }

    private func startupSettlingDiagnostics(
        reason: String
    ) -> MenuBarStartupSettlingExecutor.Diagnostics {
        MenuBarStartupSettlingExecutor.Diagnostics(
            recordWaitingForExpectedSet: { waitingFor in
                MenuBarItemManager.diagLog.debug(
                    "\(reason): waiting for \(waitingFor.count) expected bundle ID(s) to reattach"
                )
            },
            recordDeadlineReached: { deadline in
                MenuBarItemManager.diagLog.debug(
                    "\(reason): settling hit max deadline (\(deadline)), ending with fallback"
                )
            },
            recordSettled: { settledReason in
                self.recordStartupSettled(reason: reason, settledReason: settledReason)
            },
            recordWait: { waitReason in
                self.recordStartupSettlingWait(reason: reason, waitReason: waitReason)
            },
            recordCancelled: {
                MenuBarItemManager.diagLog.debug("\(reason): settling task cancelled")
            },
            recordEnded: {
                MenuBarItemManager.diagLog.debug("\(reason): settling period ended")
            },
            recordFastRestoreStart: {
                MenuBarItemManager.diagLog.debug(
                    "\(reason): running fast restore without sourcePID resolution"
                )
            }
        )
    }

    private func recordStartupSettled(
        reason: String,
        settledReason: MenuBarStartupSettlingPolicy.SettledReason
    ) {
        switch settledReason {
        case let .expectedBundleIDsReattached(count):
            MenuBarItemManager.diagLog.debug(
                "\(reason): all \(count) expected bundle ID(s) reattached, ending early"
            )
        case let .countStable(count, stablePolls, unresolvedSourcePIDCount):
            MenuBarItemManager.diagLog.debug(
                "\(reason): settled (count=\(count) stable for \(stablePolls) polls, \(unresolvedSourcePIDCount) nil PIDs), ending early"
            )
        }
    }

    private func recordStartupSettlingWait(
        reason: String,
        waitReason: MenuBarStartupSettlingPolicy.WaitReason
    ) {
        switch waitReason {
        case let .missingExpectedBundleIDs(missingBundleIDs):
            MenuBarItemManager.diagLog.debug(
                "\(reason): \(missingBundleIDs.count) bundle ID(s) still missing: \(missingBundleIDs.sorted().joined(separator: ", "))"
            )
        case let .sourcePIDsUnresolved(managedItemCount, unresolvedSourcePIDCount):
            MenuBarItemManager.diagLog.debug(
                "\(reason): waiting for sourcePIDs (count=\(managedItemCount), \(unresolvedSourcePIDCount) nil PIDs)"
            )
        case let .countChanged(previous, current, unresolvedSourcePIDCount):
            MenuBarItemManager.diagLog.debug(
                "\(reason): count changed \(previous) -> \(current) (\(unresolvedSourcePIDCount) nil PIDs), resetting stability"
            )
        case let .waitingForStableCount(count, stablePolls, target, unresolvedSourcePIDCount):
            MenuBarItemManager.diagLog.debug(
                "\(reason): count=\(count) stable for \(stablePolls)/\(target) polls (\(unresolvedSourcePIDCount) nil PIDs)"
            )
        }
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables(with appState: AppState) {
        var c = Set<AnyCancellable>()

        // When any app launches, refresh the cache to detect new menu bar items
        // (e.g., apps with "unremembered" icons that need restoration) and restore
        // any items that moved to incorrect sections after their app restarted.
        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didLaunchApplicationNotification
        )
        .debounce(for: MenuBarRuntimeRefreshPolicy.appLaunchDebounce, scheduler: DispatchQueue.main)
        .sink { [weak self] notification in
            guard let self else { return }
            let launchedBundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            MenuBarItemManager.diagLog.debug(
                "App launched\(launchedBundleID.map { " (\($0))" } ?? ""), refreshing cache for potential new items"
            )

            // If the launched app is one we already track a menu bar item for,
            // it just relaunched (e.g. an in-app update): its status item is
            // about to disappear and re-register, churning the bar for a few
            // seconds. Start a settling period keyed on its bundle ID so the
            // move pass (applySavedSectionLayout waits on waitForStartupSettlingToEnd)
            // holds off until the item has re-paired. Without this the bulk apply ran
            // on the transient layout and swept hidden items into the visible
            // section. The period exits the instant the bundle ID reappears
            // with a resolved PID (median ~3s in field logs); maxDuration is
            // only a backstop. Apps with no tracked menu bar item arm nothing,
            // so there is no deferral for ordinary launches.
            if let launchedBundleID,
               self.knownItemLedger.tracksMenuBarItem(bundleID: launchedBundleID)
            {
                self.startSettlingPeriod(
                    reason: "appLaunch",
                    expectedBundleIDs: [launchedBundleID],
                    maxDuration: MenuBarRuntimeRefreshPolicy.trackedAppLaunchSettlingDuration
                )
            }
            self.scheduleEventRefresh(
                .fullRefresh(followUpDelays: MenuBarRuntimeRefreshPolicy.appLaunchFollowUpDelays)
            )
        }
        .store(in: &c)

        // When any app terminates, refresh the cache (items may have disappeared).
        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        )
        .debounce(for: MenuBarRuntimeRefreshPolicy.appTerminationDebounce, scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            MenuBarItemManager.diagLog.debug("App terminated, refreshing cache")
            self.scheduleEventRefresh(.ifNeeded)
        }
        .store(in: &c)

        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didActivateApplicationNotification
        )
        .debounce(for: MenuBarRuntimeRefreshPolicy.appActivationDebounce, scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else {
                return
            }
            self.scheduleEventRefresh(.ifNeeded)
        }
        .store(in: &c)

        // Rescan on menu bar window-list changes. cacheItemsIfNeeded compares
        // the current items-only window IDs against the cached set and recaches
        // only when they differ, so this catches both late-registering items
        // (background-only apps like OneDrive) and the transient bundle-ID
        // marker windows that source-PID marker-pair resolution depends on,
        // which can appear and disappear between sparser app-event triggers. A
        // short interval keeps marker-pair latency low; the windowID comparison
        // bails fast and triggers no recache when nothing changed.
        cacheTickCancellable = Timer.publish(
            every: MenuBarRuntimeRefreshPolicy.cacheTickIntervalSeconds,
            on: .main,
            in: .common
        )
            .autoconnect()
            .sink { [weak self] _ in
                self?.scheduleEventRefresh(.ifNeeded)
            }

        cancellables = c
    }

    private func scheduleEventRefresh(_ request: MenuBarEventRefreshRuntime.Request) {
        switch eventRefreshRuntime.schedule(request) {
        case let .start(token, request):
            startEventRefreshTask(token: token, request: request)
        case let .coalesced(request):
            MenuBarItemManager.diagLog.debug(
                "event refresh coalesced (fullRefresh=\(request.requiresFullRefresh), followUps=\(request.followUpDelays.count))"
            )
        }
    }

    private func startEventRefreshTask(
        token: MenuBarEventRefreshRuntime.Token,
        request: MenuBarEventRefreshRuntime.Request
    ) {
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performEventRefresh(request)
            finishEventRefresh(token)
        }
        eventRefreshRuntime.attachTask(task, for: token)
    }

    private func finishEventRefresh(_ token: MenuBarEventRefreshRuntime.Token) {
        switch eventRefreshRuntime.finish(token) {
        case .idle:
            return
        case let .startNext(nextToken, request):
            startEventRefreshTask(token: nextToken, request: request)
        }
    }

    private func performEventRefresh(_ request: MenuBarEventRefreshRuntime.Request) async {
        if request.requiresFullRefresh {
            await cacheItemsRegardless()
        } else {
            await cacheItemsIfNeeded()
        }

        // Many apps register their NSStatusItem more than 1s after
        // didLaunch fires, so the initial cache pass above sees no
        // new window IDs and relocateNewLeftmostItems no-ops. Re-check
        // at +2.5s and +5s to catch late arrivals; cacheItemsIfNeeded
        // bails when window IDs are unchanged, so this is cheap when
        // the item already showed up on the first pass.
        for delay in request.followUpDelays {
            do {
                try await Task.sleep(for: delay)
            } catch is CancellationError {
                return
            } catch {
                return
            }

            await cacheItemsIfNeeded()
        }
    }

    /// Returns a Boolean value that indicates whether the most recent
    /// menu bar item move operation occurred within the given duration.
    func lastMoveOperationOccurred(within duration: Duration) -> Bool {
        syntheticEventRuntime.lastMoveOperationOccurred(within: duration)
    }

    /// Records that a move operation occurred outside of Continuum's own `move()` function
    /// (e.g. the user cmd+dragged an item directly on the menu bar).
    func recordExternalMoveOperation() {
        syntheticEventRuntime.recordMoveOperation()
    }
}

// MARK: - Item Cache

extension MenuBarItemManager {
    /// Caches the given menu bar items, without ensuring that the provided
    /// control items are correctly ordered.
    private func uncheckedCacheItems(
        items: [MenuBarItem],
        controlItems: MenuBarControlItems,
        displayID: CGDirectDisplayID?
    ) async {
        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: processing \(items.count) items for caching")
        let population = MenuBarCachePopulationRuntime.buildCache(
            items: items,
            controlItems: controlItems,
            displayID: displayID,
            temporaryContexts: temporaryRevealRuntime.cachePopulationContexts,
            currentBoundsForItem: { Bridging.getWindowBounds(for: $0.windowID) }
        )

        for item in population.duplicateItems {
            MenuBarItemManager.diagLog.debug("uncheckedCacheItems: skipping duplicate tag \(item.logString)")
        }
        for item in population.missingSourcePIDItems {
            MenuBarItemManager.diagLog.warning("Missing sourcePID for \(item.logString)")
        }
        for item in population.blockedNoSectionItems {
            MenuBarItemManager.diagLog.warning(
                "Skipping \(item.logString); blocked (x=-1), will retry on next cache tick"
            )
        }
        for item in population.hiddenFallbackItems {
            MenuBarItemManager.diagLog.warning(
                "Couldn't find section for caching \(item.logString) bounds=\(NSStringFromRect(item.bounds)), assigning to hidden"
            )
        }

        MenuBarItemManager.diagLog.debug("uncheckedCacheItems: \(population.validCount) valid, \(population.invalidCount) invalid (filtered), \(population.noSectionCount) couldn't find section, \(population.temporarilyShownCount) temporarily shown")

        let cacheDidChange = itemCache != population.cache
        guard MenuBarCacheCommitPolicy.cacheUpdateAction(cacheDidChange: cacheDidChange) == .commitCache else {
            MenuBarItemManager.diagLog.debug("Not updating menu bar item cache, as items haven't changed")
            recordRuntimeSnapshot(from: population.cache)
            return
        }

        itemCache = population.cache
        recordRuntimeSnapshot(from: population.cache)

        if layoutMutationState.clearStaleSavedLayoutRestoreIfNeeded() {
            MenuBarItemManager.diagLog.debug("Resetting stale isRestoringItemOrder flag (timeout)")
        }

        let hasBlockedItems = MenuBarCacheCommitPolicy.containsBlockedItems(in: population.cache) { item in
            Bridging.getWindowBounds(for: item.windowID)
        }
        let persistenceDecision = MenuBarCacheCommitPolicy.savedOrderPersistenceDecision(
            cacheDidChange: cacheDidChange,
            isRestoringItemOrder: layoutMutationState.isRestoringItemOrder,
            isResettingLayout: layoutMutationState.isResettingLayout,
            isInStartupSettling: startupSettlingRuntime.isActive,
            temporarilyShownItemContextsIsEmpty: temporaryRevealRuntime.isEmpty,
            hasBlockedItems: hasBlockedItems
        )
        switch persistenceDecision {
        case .persist:
            saveSectionOrder(from: population.cache)
        case .skip(.blockedItems):
            MenuBarItemManager.diagLog.debug(
                "Skipping saveSectionOrder; blocked items detected (x=-1), will retry on next cache tick"
            )
        case let .skip(reason):
            if reason != .cacheUnchanged {
                MenuBarItemManager.diagLog.debug(
                    "Skipping saveSectionOrder; \(reason.description)"
                )
            }
        }
        MenuBarItemManager.diagLog.debug("Updated menu bar item cache: visible=\(population.cache[.visible].count), hidden=\(population.cache[.hidden].count), alwaysHidden=\(population.cache[.alwaysHidden].count)")
    }

    private var isSystemMenuBarHiddenForDiagnostics: Bool {
        appState?.menuBarManager.isMenuBarHiddenBySystem == true ||
            appState?.menuBarManager.isMenuBarHiddenBySystemUserDefaults == true
    }

    /// Records an immutable snapshot for diagnostics and future control-plane reads.
    private func recordRuntimeSnapshot(
        from cache: MenuBarItemCache? = nil,
        controlItemsMissing: Bool? = nil
    ) {
        diagnosticsRuntime.recordSnapshot(
            cache: cache ?? itemCache,
            controlItemsMissing: controlItemsMissing,
            systemMenuBarHidden: isSystemMenuBarHiddenForDiagnostics
        )
    }

    private func recordZeroItemObservation(detail: String) {
        diagnosticsRuntime.recordZeroItemObservation(
            preserving: itemCache,
            systemMenuBarHidden: isSystemMenuBarHiddenForDiagnostics,
            detail: detail
        )
    }

    private func resolvedControlItemWindowID(for section: MenuBarSection.Name) -> CGWindowID? {
        appState?.menuBarManager
            .controlItem(withName: section)?.resolvedWindow()
            .flatMap { CGWindowID(exactly: $0.windowNumber) }
    }

    private func resolvedControlItemWindowIDs() -> MenuBarControlItemWindowIDs {
        MenuBarControlItemWindowIDs(
            visible: resolvedControlItemWindowID(for: .visible),
            hidden: resolvedControlItemWindowID(for: .hidden),
            alwaysHidden: resolvedControlItemWindowID(for: .alwaysHidden)
        )
    }

    private func cacheCycleContinuationDiagnostics() -> MenuBarCacheCycleContinuationExecutor.Diagnostics {
        MenuBarCacheCycleContinuationExecutor.Diagnostics(
            recordCancelledAfterControlDiscovery: {
                MenuBarItemManager.diagLog.debug(
                    "cacheItemsRegardless: cancelled after control item discovery"
                )
            },
            recordCancelledBeforeRelocation: {
                MenuBarItemManager.diagLog.debug(
                    "cacheItemsRegardless: cancelled before relocateNewLeftmostItems"
                )
            },
            recordStartupSettlingCached: {
                MenuBarItemManager.diagLog.debug(
                    "cacheItemsRegardless: startup settling active, skipping restore"
                )
            }
        )
    }

    private func scheduleCacheCycleFollowUpRecache(
        reason: MenuBarCacheCyclePolicy.RelocationReason
    ) {
        MenuBarItemManager.diagLog.debug("\(reason.description); scheduling recache")
        switch cacheRuntime.scheduleFollowUpRecache() {
        case let .start(token):
            startCacheCycleFollowUpRecache(token)
        case .waitForRunningFollowUp:
            MenuBarItemManager.diagLog.debug(
                "\(reason.description); follow-up recache already running, scheduling another pass"
            )
        }
    }

    private func startCacheCycleFollowUpRecache(
        _ token: MenuBarCacheCycleRuntime.FollowUpToken
    ) {
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
            } catch is CancellationError {
                return
            } catch {
                return
            }

            guard cacheRuntime.beginFollowUpRecache(token) else {
                return
            }

            await cacheItemsRegardless(skipRecentMoveCheck: true)
            finishCacheCycleFollowUpRecache(token)
        }
        cacheRuntime.attachFollowUpTask(task, for: token)
    }

    private func finishCacheCycleFollowUpRecache(
        _ token: MenuBarCacheCycleRuntime.FollowUpToken
    ) {
        switch cacheRuntime.finishFollowUpRecache(token) {
        case .idle:
            return
        case let .startNext(nextToken):
            startCacheCycleFollowUpRecache(nextToken)
        }
    }

    /// Caches the current menu bar items, regardless of whether the
    /// items have changed since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsRegardless(
        _ currentItemWindowIDs: [CGWindowID]? = nil,
        skipRecentMoveCheck: Bool = false,
        resolveSourcePID: Bool = true,
        skipSavedLayoutApply: Bool = false
    ) async {
        MenuBarItemManager.diagLog.debug(
            "cacheItemsRegardless: entering (skipRecentMoveCheck=\(skipRecentMoveCheck), hasCurrentItemWindowIDs=\(currentItemWindowIDs != nil), resolveSourcePID=\(resolveSourcePID), skipSavedLayoutApply=\(skipSavedLayoutApply))"
        )
        diagnosticsRuntime.markState(.observing)
        defer {
            cacheRuntime.resumeBackgroundContinuation()
        }

        switch MenuBarCacheAdmissionPolicy.preGateDecision(
            skipRecentMoveCheck: skipRecentMoveCheck,
            recentMoveOccurred: lastMoveOperationOccurred(
                within: MenuBarCacheAdmissionPolicy.recentMoveQuietWindow
            ),
            userIsDraggingMenuBarItem: appState?.isDraggingMenuBarItem ?? false
        ) {
        case .attemptGate:
            break
        case .skip(.recentMove):
            MenuBarItemManager.diagLog.debug("Skipping menu bar item cache due to recent item movement")
            diagnosticsRuntime.markState(.idle)
            return
        case .skip(.userDragging):
            MenuBarItemManager.diagLog.debug("Skipping menu bar item cache: user is cmd-dragging")
            diagnosticsRuntime.markState(.idle)
            return
        case let .skip(reason):
            MenuBarItemManager.diagLog.debug("Skipping menu bar item cache: \(reason.description)")
            diagnosticsRuntime.markState(.idle)
            return
        }

        // Serialization gate: drop concurrent calls while a previous cache
        // cycle is in flight. Without this, a call that starts during a
        // relocation move by another call may snapshot pre-move positions.
        switch MenuBarCacheAdmissionPolicy.gateDecision(
            cacheGateAcquired: await cacheRuntime.operationGate.begin()
        ) {
        case .run:
            break
        case .skip(.cacheInProgress):
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: serial cache operation already in progress, skipping")
            diagnosticsRuntime.markState(.idle)
            return
        case let .skip(reason):
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: \(reason.description), skipping")
            diagnosticsRuntime.markState(.idle)
            return
        }
        let cacheGate = cacheRuntime.operationGate
        defer { Task { await cacheGate.end() } }

        let previousWindowIDs = cacheRuntime.cachedItemWindowIDs
        let displayID = Bridging.getActiveMenuBarDisplayID()
        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: displayID=\(displayID.map { "\($0)" } ?? "nil"), previousWindowIDs count=\(previousWindowIDs.count)")

        let observationResult: MenuBarObservationRuntime.Result
        switch await MenuBarObservationRuntime.observe(
            displayID: displayID,
            currentItemWindowIDs: currentItemWindowIDs,
            previousWindowIDs: previousWindowIDs,
            previousSourcePIDs: cacheRuntime.cachedItemPIDs,
            knownItemIdentifiers: knownItemLedger.identifiers,
            resolveSourcePID: resolveSourcePID,
            itemProvider: { resolveSourcePID in
                await MenuBarItem.getMenuBarItems(
                    option: .activeSpace,
                    resolveSourcePID: resolveSourcePID
                )
            },
            bundleIdentifierForPID: { pid in
                NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            }
        ) {
        case let .observed(result):
            observationResult = result
        case let .zeroItems(failure):
            MenuBarItemManager.diagLog.error(
                "cacheItemsRegardless: getMenuBarItems returned ZERO items after \(failure.attempts) attempt(s); this is the root cause of 'Loading menu bar items' being stuck"
            )
            recordZeroItemObservation(detail: failure.detail)
            return
        }

        var items = observationResult.items
        let observation = observationResult.observation
        MenuBarItemManager.diagLog.debug(
            "cacheItemsRegardless: getMenuBarItems returned \(items.count) items after \(observationResult.attempts) attempt(s)"
        )

        if observation.cloneCount > 0 {
            MenuBarItemManager.diagLog.debug(
                "cacheItemsRegardless: dropping \(observation.cloneCount) system clone window(s): \(observation.droppedCloneDescriptions)"
            )
            diagnosticsRuntime.recordCloneWindowsDropped(observation.cloneCount)
        }

        for correction in observationResult.identityCorrections {
            MenuBarItemManager.diagLog.warning(
                "SourcePID changed for windowID \(correction.windowID): \(correction.previousPID) -> \(correction.observedPID), reverting to previous PID"
            )
        }
        diagnosticsRuntime.recordIdentityCorrections(observationResult.identityCorrections.count)

        if knownItemLedger.remember(observationResult.identifiersToSeed) {
            persistKnownItemIdentifiers()
        }

        guard !Task.isCancelled else {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: cancelled after getMenuBarItems")
            return
        }

        // currentItemWindowIDs comes straight from the bridging window list
        // and may still contain clone IDs; the observation frame strips them
        // so stored window IDs stay in sync with the managed item set.
        let itemWindowIDs = observation.normalizedWindowIDs
        cacheRuntime.recordObservation(
            itemWindowIDs: itemWindowIDs,
            cloneWindowIDs: observation.droppedCloneWindowIDs
        )

        await MainActor.run {
            MenuBarItemTag.Namespace.pruneUUIDCache(keeping: Set(itemWindowIDs))
            self.syntheticEventRuntime.pruneTimeouts(keeping: items)
        }

        // Obtain window IDs from the actual ControlItem objects so the
        // fallback lookup in MenuBarControlItems can match by window ID when
        // the tag-based and title-based lookups fail (macOS 26+).
        let controlItemWindowIDs = resolvedControlItemWindowIDs()

        let discoveredControlItems = MenuBarControlItems(
            items: &items,
            windowIDs: controlItemWindowIDs
        )

        switch MenuBarCacheCyclePolicy.controlItemDecision(
            controlItemsFound: discoveredControlItems != nil
        ) {
        case .continueCycle:
            break
        case .preserveKnownGoodCache:
            MenuBarItemManager.diagLog.warning("cacheItemsRegardless: Missing control item for hidden section (expected tag: \(MenuBarItemTag.hiddenControlItem)), preserving last good cache. Items remaining: \(items.count), windowIDs: \(itemWindowIDs.count). hiddenControlItemWID=\(controlItemWindowIDs.hidden.map { "\($0)" } ?? "nil"), alwaysHiddenControlItemWID=\(controlItemWindowIDs.alwaysHidden.map { "\($0)" } ?? "nil")")
            diagnosticsRuntime.recordControlItemMiss(
                detail: "Hidden control item missing during cache; items=\(items.count), windowIDs=\(itemWindowIDs.count)",
                preserving: itemCache,
                systemMenuBarHidden: isSystemMenuBarHiddenForDiagnostics
            )
            return
        }
        guard let controlItems = discoveredControlItems else {
            return
        }

        diagnosticsRuntime.markControlItemsAvailable()

        MenuBarItemManager.diagLog.debug("cacheItemsRegardless: found control items, hidden windowID=\(controlItems.hidden.windowID), alwaysHidden=\(controlItems.alwaysHidden.map { "\($0.windowID)" } ?? "nil")")

        let continuationOutcome = await MenuBarCacheCycleContinuationExecutor.execute(
            input: MenuBarCacheCycleContinuationExecutor.Input(
                items: items,
                controlItems: controlItems,
                previousWindowIDs: previousWindowIDs,
                previousDisplayID: itemCache.displayID,
                currentDisplayID: displayID,
                isInStartupSettling: startupSettlingRuntime.isActive,
                skipSavedLayoutApply: skipSavedLayoutApply,
                resolveSourcePID: resolveSourcePID
            ),
            operations: MenuBarCacheCycleContinuationExecutor.Operations(
                taskIsCancelled: {
                    Task.isCancelled
                },
                enforceControlItemOrder: { controlItems in
                    await self.enforceControlItemOrder(controlItems: controlItems)
                },
                relocateNewLeftmostItems: { items, controlItems, previousWindowIDs in
                    await self.relocateNewLeftmostItems(
                        items,
                        controlItems: controlItems,
                        previousWindowIDs: previousWindowIDs
                    )
                },
                relocatePendingItems: { items, controlItems in
                    await self.relocatePendingItems(items, controlItems: controlItems)
                },
                scheduleFollowUpRecache: { reason in
                    self.scheduleCacheCycleFollowUpRecache(reason: reason)
                },
                cacheObservation: { items, controlItems, displayID in
                    await self.uncheckedCacheItems(
                        items: items,
                        controlItems: controlItems,
                        displayID: displayID
                    )
                },
                applySavedLayout: { items, previousWindowIDs, controlItems, previousDisplayID, currentDisplayID in
                    // Unified saved-layout restore: dispatch the bulk apply path
                    // when window IDs have changed (app relaunch). applySavedLayout
                    // owns its own cooldown and guard checks; the bulk mover arms
                    // layoutMutationState around the moves and drives its own
                    // follow-up recache. On rejection the flag is left false so
                    // saveSectionOrder can persist the current cache.
                    self.diagnosticsRuntime.markState(.planning)
                    return await self.applySavedLayout(
                        items: items,
                        previousWindowIDs: previousWindowIDs,
                        controlItems: controlItems,
                        previousDisplayID: previousDisplayID,
                        currentDisplayID: currentDisplayID
                    )
                },
                recordResolvedSourcePIDs: { pids in
                    self.cacheRuntime.recordResolvedSourcePIDs(pids)
                }
            ),
            diagnostics: cacheCycleContinuationDiagnostics()
        )

        if continuationOutcome.stopReason == .committedCache {
            MenuBarItemManager.diagLog.debug("cacheItemsRegardless: finished, cache now has \(self.itemCache.managedItems.count) managed items")
        }
    }

    /// Caches the current menu bar items, if the items have changed
    /// since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsIfNeeded() async {
        let rawWindowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])
        // Exclude windowIDs already known to be system clones so their
        // churn doesn't read as a layout change. A brand-new clone whose
        // windowID hasn't been learned yet still triggers one recache,
        // which resolves it, records it, and drops it; from then on its
        // presence and removal are ignored.
        let cachedIDs = cacheRuntime.cachedItemWindowIDs
        let cloneIDs = cacheRuntime.cachedCloneWindowIDs
        let decision = MenuBarCacheInvalidation.evaluate(
            cachedWindowIDs: cachedIDs,
            observedWindowIDs: rawWindowIDs,
            cloneWindowIDs: cloneIDs
        )
        if decision.shouldRecache {
            MenuBarItemManager.diagLog.debug("cacheItemsIfNeeded: window IDs changed (\(cachedIDs.count) cached vs \(decision.normalizedWindowIDs.count) current), triggering recache")
            await cacheItemsRegardless(decision.normalizedWindowIDs)
        }
    }
}

// MARK: - Event Helpers

extension MenuBarItemManager {
    private func acquireEventOperationPermit(
        context: String,
        item: MenuBarItem? = nil
    ) async throws -> MenuBarEventOperationGate.Permit {
        do {
            let permit = try await syntheticEventRuntime.operationGate.acquire()
            if permit.recoveredFromTimeout {
                MenuBarItemManager.diagLog.error(
                    "\(context): event operation gate timed out (\(Int(MenuBarEventOperationGate.defaultAcquireTimeout.milliseconds))ms); reset and acquired\(item.map { " for \($0.logString)" } ?? "")"
                )
            }
            return permit
        } catch MenuBarEventOperationGate.AcquireError.timedOutAfterReset {
            MenuBarItemManager.diagLog.error(
                "\(context): event operation gate timed out after reset\(item.map { " for \($0.logString)" } ?? "")"
            )
            throw MenuBarEventError.cannotComplete
        } catch {
            throw MenuBarEventError.cannotComplete
        }
    }

    private func currentMoveOperationBuffer() -> Duration? {
        syntheticEventRuntime.moveOperationBuffer()
    }

    /// Returns a Boolean value that indicates whether the user has
    /// paused input for at least the given duration.
    ///
    /// - Parameter duration: The duration that certain types of input
    ///   events must not have occured within in order to return `true`.
    private nonisolated func hasUserPausedInput(for duration: Duration) -> Bool {
        NSEvent.modifierFlags.isEmpty &&
            !MouseHelpers.lastMovementOccurred(within: duration) &&
            !MouseHelpers.lastScrollWheelOccurred(within: duration) &&
            !MouseHelpers.isButtonPressed()
    }

    /// Waits asynchronously for the user to pause input.
    private nonisolated func waitForUserToPauseInput() async throws {
        let waitTask = Task {
            while true {
                try Task.checkCancellation()
                if hasUserPausedInput(for: MenuBarEventPacingPolicy.inputPauseQuietWindow) {
                    break
                }
                try await Task.sleep(for: MenuBarEventPacingPolicy.inputPausePollInterval)
            }
        }
        do {
            try await waitTask.value
        } catch {
            throw MenuBarEventError.cannotComplete
        }
    }

    /// Waits between move operations for a dynamic amount of time,
    /// based on the timestamp of the last move operation.
    private nonisolated func waitForMoveOperationBuffer() async throws {
        if let buffer = await currentMoveOperationBuffer() {
            MenuBarItemManager.diagLog.debug("Move operation buffer: \(buffer)")
            do {
                try await Task.sleep(for: buffer)
            } catch {
                throw MenuBarEventError.cannotComplete
            }
        }
    }

    /// Waits for the given duration between event operations.
    ///
    /// Since most event operations must perform cleanup or otherwise
    /// run to completion, this method ignores task cancellation.
    private nonisolated func eventSleep(
        for duration: Duration = MenuBarEventPacingPolicy.defaultEventSleep
    ) async {
        let task = Task {
            try? await Task.sleep(for: duration)
        }
        await task.value
    }

    /// Returns the current bounds for the given item, with a refresh fallback if the window is missing.
    private nonisolated func getCurrentBounds(for item: MenuBarItem) async throws -> CGRect {
        // First attempt: current windowID.
        if let bounds = Bridging.getWindowBounds(for: item.windowID) {
            return bounds
        }

        // Fallback: refresh on-screen items and pick the matching tag (prefer same windowID, then non-clone).
        let refreshed = await MenuBarItem.getMenuBarItems(option: .onScreen)
        if let refreshedItem = refreshed.first(where: { $0.windowID == item.windowID && $0.tag == item.tag }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) && !$0.isSystemClone }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) })
        {
            return refreshedItem.bounds
        }

        throw MenuBarEventError.missingItemBounds(item)
    }

    /// Returns the current mouse location.
    private nonisolated func getMouseLocation() throws -> CGPoint {
        guard let location = MouseHelpers.locationCoreGraphics else {
            throw MenuBarEventError.missingMouseLocation
        }
        return location
    }

    private nonisolated func getHotCornerSafeMouseLocation() throws -> CGPoint {
        MenuBarMoveGeometryPolicy.hotCornerSafePoint(
            try getMouseLocation(),
            screenFrames: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
        )
    }

    /// Returns the process identifier that can be used to create
    /// and post a menu bar item event.
    private nonisolated func getEventPID(for item: MenuBarItem) -> pid_t {
        item.sourcePID ?? item.ownerPID
    }

    /// Posts an event to the given menu bar item and waits until
    /// it is received before returning.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The base duration to wait before throwing an error.
    ///     The value of this parameter is multiplied by `count` to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling `postEventWithBarrier`.
    private nonisolated func postEventWithBarrier(
        _ event: CGEvent,
        to item: MenuBarItem,
        timeout: Duration,
        repeating count: Int = 1
    ) async throws {
        try await MenuBarEventContinuationRuntime.perform(
            mode: .postEventBarrier,
            event: event,
            item: item,
            pid: getEventPID(for: item),
            timeout: timeout,
            repeating: count
        )
    }

    /// Casts forbidden magic to make a menu bar item receive and
    /// respond to an event during a move operation.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The base duration to wait before throwing an error.
    ///     The value of this parameter is multiplied by `count` to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling `scrombleEvent`.
    private nonisolated func scrombleEvent(
        _ event: CGEvent,
        item: MenuBarItem,
        timeout: Duration,
        repeating count: Int = 1
    ) async throws {
        try await MenuBarEventContinuationRuntime.perform(
            mode: .scromble,
            event: event,
            item: item,
            pid: getEventPID(for: item),
            timeout: timeout,
            repeating: count
        )
    }
}

// MARK: - Moving Items

extension MenuBarItemManager {
    /// Returns the target points for creating the events needed to
    /// move a menu bar item to the given destination.
    private nonisolated func getTargetPoints(
        forMoving item: MenuBarItem,
        to destination: MenuBarMoveDestination,
        on displayID: CGDirectDisplayID
    ) async throws -> MenuBarMoveGeometryPolicy.EventPoints {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)
        let points = MenuBarMoveGeometryPolicy.eventPoints(
            for: destination,
            targetBounds: targetBounds
        )

        MenuBarItemManager.diagLog.debug(
            "Move points: startX=\(points.start.x) endX=\(points.end.x) startY=\(points.start.y) targetMinX=\(targetBounds.minX) itemMinX=\(itemBounds.minX) targetTag=\(destination.targetItem.tag) itemTag=\(item.tag) display=\(displayID)"
        )
        return points
    }

    /// Returns a Boolean value that indicates whether the given menu bar
    /// item has the correct position, relative to the given destination.
    private nonisolated func itemHasCorrectPosition(
        item: MenuBarItem,
        for destination: MenuBarMoveDestination,
        on _: CGDirectDisplayID
    ) async throws -> Bool {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)
        return switch destination {
        case .leftOfItem: itemBounds.maxX == targetBounds.minX
        case .rightOfItem: itemBounds.minX == targetBounds.maxX
        }
    }

    /// Waits for a menu bar item to respond to a series of previously
    /// posted move events.
    ///
    /// - Parameters:
    ///   - item: The item to check for a response.
    ///   - initialOrigin: The origin of the item before the events were posted.
    ///   - timeout: The duration to wait before throwing an error.
    private nonisolated func waitForMoveEventResponse(
        from item: MenuBarItem,
        initialOrigin: CGPoint,
        timeout: Duration
    ) async throws -> CGPoint {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }
        let responseTask = Task.detached {
            while true {
                try Task.checkCancellation()
                let origin = try await self.getCurrentBounds(for: item).origin
                if origin != initialOrigin {
                    return origin
                }
                try await Task.sleep(for: MenuBarEventPacingPolicy.moveResponsePollInterval)
            }
        }
        let timeoutTask = Task(timeout: timeout) {
            try await withTaskCancellationHandler {
                try await responseTask.value
            } onCancel: {
                responseTask.cancel()
            }
        }
        do {
            let origin = try await timeoutTask.value
            MenuBarItemManager.diagLog.debug(
                """
                Item responded to events with new origin: \
                \(String(describing: origin))
                """
            )
            return origin
        } catch let error as MenuBarEventError {
            throw error
        } catch is TaskTimeoutError {
            throw MenuBarEventError.itemResponseTimeout(item)
        } catch {
            throw MenuBarEventError.cannotComplete
        }
    }

    /// Creates and posts a series of events to move a menu bar item
    /// to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the menu bar item.
    private func postMoveEvents(
        item: MenuBarItem,
        destination: MenuBarMoveDestination,
        on displayID: CGDirectDisplayID,
        warpCursorAfter: Bool = true
    ) async throws {
        _ = try await acquireEventOperationPermit(context: "postMoveEvents", item: item)
        let operationGate = syntheticEventRuntime.operationGate
        defer {
            Task.detached { await operationGate.release() }
        }

        // Fast-fail if the target process is dead. CGEvent.tapCreateForPid
        // silently produces an invalid Mach port for dead PIDs, causing every
        // scrombleEvent to time out and burn the full event-gate budget.
        let eventPID = getEventPID(for: item)
        if kill(eventPID, 0) == -1, errno == ESRCH {
            MenuBarItemManager.diagLog.error("postMoveEvents: target PID \(eventPID) for \(item.logString) is dead; skipping move")
            throw MenuBarEventError.cannotComplete
        }

        var itemOrigin = try await getCurrentBounds(for: item).origin
        let targetPoints = try await getTargetPoints(forMoving: item, to: destination, on: displayID)
        // Capture mouse location only when this call owns the cursor warp.
        // When called from move(), the outer move() handles the single warp
        // at the end of all attempts so the cursor doesn't oscillate per attempt.
        let mouseLocation: CGPoint? = warpCursorAfter ? try getHotCornerSafeMouseLocation() : nil
        let source = try MenuBarEventSourceRuntime.source()

        try MenuBarEventSourceRuntime.permitLocalEvents()

        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .move(.mouseDown),
                location: targetPoints.start
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                item: destination.targetItem,
                source: source,
                type: .move(.mouseUp),
                location: targetPoints.end
            )
        else {
            throw MenuBarEventError.eventCreationFailure(item)
        }

        var timeout = syntheticEventRuntime.moveTimeout(for: item)
        MenuBarItemManager.diagLog.debug("Move operation timeout: \(timeout)")

        syntheticEventRuntime.recordMoveOperation()
        // Skip the warp when the target is offscreen (negative-X items in
        // hidden/always-hidden on notch displays). CGWarpMouseCursorPosition
        // clamps to the display's leftmost edge, which sits under the Apple
        // menu, and the resulting tracking events then route stray clicks
        // there. The post-warp settle delay is only needed
        // when slow apps have to register the tracking events before the
        // mouseDown; irrelevant offscreen.
        let warpPoint = targetPoints.start
        let screens = NSScreen.screens
        let warpDecision = MenuBarMoveGeometryPolicy.cursorWarpDecision(
            warpPoint: warpPoint,
            screenFrames: screens.map(\.frame)
        )
        if warpDecision.shouldWarpCursor {
            MouseHelpers.warpCursor(to: warpPoint)
        }
        // In a batch apply the cursor is already hidden for the whole
        // sequence; re-hiding (and the matching showCursor below) per attempt
        // is what makes it flash. Skip both when the batch owns the cursor.
        if syntheticEventRuntime.shouldManageCursor {
            MouseHelpers.hideCursor()
        }
        if warpDecision.shouldWaitForWarpSettle {
            await eventSleep(for: MenuBarEventPacingPolicy.moveWarpSettleDelay)
        }
        // For notched displays, when the target is offscreen, redirect
        // mouseDown's hit-test location into the notch itself. The
        // notch is hardware with no clickable UI, so the OS hit-test
        // there has nothing to dismiss, no menu to open, and no app
        // window to surface a click against. mouseUp keeps its
        // original location (the drop position the receiving app
        // uses to place the item). For non-notched displays the
        // original behaviour is preserved (no override).
        let activeScreen = screens.first(where: { $0.displayID == displayID }) ?? NSScreen.main
        let activeScreenNotchFrame = activeScreen?.hasNotch == true
            ? activeScreen?.frameOfNotch
            : nil
        mouseDown.location = MenuBarMoveGeometryPolicy.mouseDownLocation(
            originalLocation: targetPoints.start,
            warpDecision: warpDecision,
            activeScreenNotchFrame: activeScreenNotchFrame
        )
        defer {
            if let mouseLocation {
                MouseHelpers.warpCursor(to: mouseLocation)
            }
            if syntheticEventRuntime.shouldManageCursor {
                MouseHelpers.showCursor()
            }
            syntheticEventRuntime.recordMoveFinished(timeout: timeout, for: item)
        }

        do {
            try await scrombleEvent(
                mouseDown,
                item: item,
                timeout: timeout
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
            try await scrombleEvent(
                mouseUp,
                item: item,
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
            timeout -= timeout / 4
        } catch {
            do {
                MenuBarItemManager.diagLog.warning("Move events failed, posting fallback")
                try await scrombleEvent(
                    mouseUp,
                    item: item,
                    timeout: MenuBarEventPacingPolicy.moveFallbackMouseUpTimeout,
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
            } catch {
                // Catch this for logging purposes only. We want to propagate
                // the original error.
                MenuBarItemManager.diagLog.error("Fallback failed with error: \(error)")
            }
            timeout += timeout / 2
            throw error
        }
    }

    /// Checks if a menu bar item is in a "blocked" state (positioned at x=-1 off-screen).
    /// Items in this state are stuck and cannot be interacted with normally.
    private nonisolated func isItemBlocked(_ item: MenuBarItem) async -> Bool {
        do {
            let bounds = try await getCurrentBounds(for: item)
            // x=-1 is the sentinel value macOS uses for "blocked" items
            return bounds.origin.x == -1
        } catch {
            // If we can't get bounds, assume it's not blocked
            return false
        }
    }

    /// Validates that an item moved toward the always-hidden section didn't
    /// get stuck at x=-1. If the item is blocked, attempts to restore it to
    /// the visible section.
    private func validateItemPositionAfterMove(
        command: MenuBarMoveCommand,
        on displayID: CGDirectDisplayID
    ) async {
        _ = await MenuBarBlockedMoveRecoveryExecutor.execute(
            command: command,
            displayID: displayID,
            itemIsBlocked: { await isItemBlocked(command.item) },
            controlItemWindowIDs: resolvedControlItemWindowIDs(),
            observeItems: {
                await observeActiveMenuBarItemsForRuntimeMutation(context: "blockedMoveRecovery")
            },
            moveItem: { item, destination, displayID in
                try await move(
                    item: item,
                    to: destination,
                    on: displayID,
                    skipInputPause: true
                )
            },
            recordRecoveryStart: { item in
                MenuBarItemManager.diagLog.warning(
                    "Item \(item.logString) stuck at x=-1 after move - attempting recovery"
                )
            },
            recordMissingHiddenControlWindow: { _ in
                MenuBarItemManager.diagLog.error(
                    "Cannot recover item: missing hidden control item window"
                )
            },
            recordHiddenControlItemMissing: { _ in
                MenuBarItemManager.diagLog.error(
                    "Cannot recover item: control item not found in menu bar items"
                )
            },
            recordRecoverySuccess: { item in
                MenuBarItemManager.diagLog.info(
                    "Successfully recovered \(item.logString) from blocked state to visible section"
                )
            },
            recordRecoveryFailure: { item, error in
                MenuBarItemManager.diagLog.error(
                    "Failed to recover \(item.logString) from blocked state: \(error)"
                )
            }
        )
    }

    /// Moves a menu bar item to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the item to.
    func move(
        item: MenuBarItem,
        to destination: MenuBarMoveDestination,
        on displayID: CGDirectDisplayID? = nil,
        skipInputPause: Bool = false,
        watchdogTimeout: DispatchTimeInterval? = nil,
        maxMoveAttempts: Int = 8
    ) async throws {
        guard let appState else {
            throw MenuBarEventError.cannotComplete
        }

        let command = MenuBarMoveCommand(
            item: item,
            destination: destination,
            displayID: displayID,
            skipInputPause: skipInputPause,
            watchdogTimeout: watchdogTimeout,
            maxMoveAttempts: maxMoveAttempts
        )
        let itemIsBlocked = await isItemBlocked(item)
        let resolvedDisplayID = MenuBarDisplayResolutionPolicy.moveDisplayID(
            explicitDisplayID: command.displayID,
            bestScreenDisplayID: appState.hidEventManager.bestScreen(appState: appState)?.displayID,
            activeMenuBarDisplayID: Bridging.getActiveMenuBarDisplayID(),
            mainDisplayID: CGMainDisplayID()
        )

        _ = try await MenuBarMoveSessionExecutor.execute(
            command: command,
            itemIsBlocked: itemIsBlocked,
            resolvedDisplayID: resolvedDisplayID,
            operations: MenuBarMoveSessionExecutor.Operations(
                taskIsCancelled: {
                    Task.isCancelled
                },
                waitForUserToPauseInput: {
                    try await self.waitForUserToPauseInput()
                },
                stopHIDEvents: {
                    appState.hidEventManager.stopAll()
                },
                startHIDEvents: {
                    appState.hidEventManager.startAll()
                },
                waitForMoveOperationBuffer: {
                    try await self.waitForMoveOperationBuffer()
                },
                itemHasCorrectPosition: { command, displayID in
                    try await self.itemHasCorrectPosition(
                        item: command.item,
                        for: command.destination,
                        on: displayID
                    )
                },
                shouldManageCursor: {
                    self.syntheticEventRuntime.shouldManageCursor
                },
                mouseLocation: {
                    try self.getHotCornerSafeMouseLocation()
                },
                hideCursor: { timeout in
                    MouseHelpers.hideCursor(watchdogTimeout: timeout)
                },
                warpCursor: { point in
                    MouseHelpers.warpCursor(to: point)
                },
                showCursor: {
                    MouseHelpers.showCursor()
                },
                postMoveEvents: { command, displayID in
                    try await self.postMoveEvents(
                        item: command.item,
                        destination: command.destination,
                        on: displayID,
                        warpCursorAfter: false
                    )
                },
                validateItemPositionAfterMove: { command, displayID in
                    await self.validateItemPositionAfterMove(
                        command: command,
                        on: displayID
                    )
                },
                recordOperationFailure: { detail in
                    self.diagnosticsRuntime.recordOperationFailure(detail: detail)
                }
            ),
            diagnostics: moveSessionDiagnostics()
        )
    }

    private func moveSessionDiagnostics() -> MenuBarMoveSessionExecutor.Diagnostics {
        MenuBarMoveSessionExecutor.Diagnostics(
            recordBlockedMoveAllowed: { item in
                MenuBarItemManager.diagLog.debug(
                    "Proceeding with move of blocked \(item.logString); recovery to visible"
                )
            },
            recordNoOp: { item, reason in
                MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - \(reason)")
            },
            recordRejected: { item, reason in
                MenuBarItemManager.diagLog.warning("Rejecting move for \(item.logString) - \(reason)")
            },
            recordMoveStart: { command, displayID in
                MenuBarItemManager.diagLog.info(
                    """
                    Moving \(command.item.logString) to \
                    \(command.destination.logString) on display \(displayID)
                    """
                )
            },
            recordAlreadyAtDestination: {
                MenuBarItemManager.diagLog.debug("Item has correct position, cancelling move")
            },
            recordAcceptedPositionMatch: {
                MenuBarItemManager.diagLog.debug("Item has correct position, finished with move")
            },
            recordPossibleFalsePositive: { attempt in
                MenuBarItemManager.diagLog.debug(
                    """
                    Position match without observable displacement on attempt \(attempt); \
                    treating as false positive on a zero-width control item and retrying
                    """
                )
            },
            recordAttemptVerified: { attempt in
                MenuBarItemManager.diagLog.debug(
                    "Attempt \(attempt) succeeded and verified, finished with move"
                )
            },
            recordAttemptUnverified: { attempt in
                MenuBarItemManager.diagLog.debug(
                    "Attempt \(attempt) events succeeded but item not at destination, retrying"
                )
            },
            recordAttemptFailed: { attempt, error in
                MenuBarItemManager.diagLog.debug("Attempt \(attempt) failed: \(error)")
            },
            recordAttemptsExhausted: { execution in
                MenuBarItemManager.diagLog.error(
                    """
                    move: all \(execution.maxAttempts) attempt(s) exhausted without \
                    verifying \(execution.command.item.logString) reached \
                    \(execution.command.destination.logString)
                    """
                )
            }
        )
    }
}

// MARK: - Clicking Items

extension MenuBarItemManager {
    /// Returns the equivalent event subtypes for clicking a menu bar
    /// item with the given mouse button.
    /// Creates and posts a series of events to click a menu bar item.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    private func postClickEvents(item: MenuBarItem, mouseButton: CGMouseButton) async throws {
        _ = try await acquireEventOperationPermit(context: "postClickEvents", item: item)
        let operationGate = syntheticEventRuntime.operationGate
        defer {
            Task.detached { await operationGate.release() }
        }

        let clickBounds = try await getCurrentBounds(for: item)
        let clickPoint = MenuBarClickTargetPolicy.clickPoint(for: clickBounds)

        let mouseLocation = try getHotCornerSafeMouseLocation()
        let source = try MenuBarEventSourceRuntime.source()

        try MenuBarEventSourceRuntime.permitLocalEvents()

        let clickTypes = MenuBarSyntheticEventType.clickSubtypes(for: mouseButton)
        // Use adaptive timeout based on app performance history
        let timeout = syntheticEventRuntime.clickTimeout(for: item)

        MenuBarItemManager.diagLog.debug("postClickEvents: using timeout \(Int(timeout.milliseconds))ms for \(item.logString)")

        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .click(clickTypes.down),
                location: clickPoint
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .click(clickTypes.up),
                location: clickPoint
            )
        else {
            throw MenuBarEventError.eventCreationFailure(item)
        }

        MouseHelpers.hideCursor(watchdogTimeout: .seconds(10))
        // Warp the cursor to the click point so the Window Server's hit-test
        // matches the event coordinates rather than the cursor's current position.
        // Hide/decouple first so this synthetic warp cannot visibly enter a
        // user-configured macOS hot corner.
        MouseHelpers.warpCursor(to: clickPoint)
        // Small delay to let the Window Server process the warp before posting
        // the event. Without this, the event can be routed using the cursor's
        // old position (e.g. the Apple menu) instead of the warped target.
        try await Task.sleep(for: MenuBarEventPacingPolicy.clickWarpSettleDelay)
        defer {
            MouseHelpers.warpCursor(to: mouseLocation)
            MouseHelpers.showCursor()
        }

        let eventStartTime = Date.now
        do {
            try await postEventWithBarrier(
                mouseDown,
                to: item,
                timeout: timeout
            )
            try await postEventWithBarrier(
                mouseUp,
                to: item,
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )

            // Update timeout cache with successful duration
            let successDuration = Duration.milliseconds(Date.now.timeIntervalSince(eventStartTime) * 1000)
            let clamped = syntheticEventRuntime.recordClickSuccess(successDuration, for: item)
            MenuBarItemManager.diagLog.debug("Updated click timeout for \(item.logString): \(Int(clamped.milliseconds))ms (measured: \(Int(successDuration.milliseconds))ms)")
        } catch {
            do {
                MenuBarItemManager.diagLog.warning("Click events failed, posting fallback")
                try await postEventWithBarrier(
                    mouseUp,
                    to: item,
                    timeout: timeout,
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
            } catch {
                // Catch this for logging purposes only. We want to propagate
                // the original error.
                MenuBarItemManager.diagLog.error("Fallback failed with error: \(error)")
            }
            throw error
        }
    }

    /// Activates a menu bar item by opening its menu, choosing the correct
    /// path based on whether the item is currently on screen.
    ///
    /// On-screen items are clicked in place. Off-screen items (in the hidden
    /// or always-hidden section) are routed through temporarilyShow, which
    /// moves, clicks, and rehides the item internally.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to activate.
    ///   - displayID: The display whose menu bar hosts a temporary reveal for
    ///     off-screen items.
    func activate(
        item: MenuBarItem,
        on displayID: CGDirectDisplayID?,
        mouseButton: CGMouseButton = .left,
        fastPath: Bool = false
    ) async {
        switch MenuBarClickTargetPolicy.activationRoute(
            itemIsOnScreen: Bridging.isWindowOnScreen(item.windowID)
        ) {
        case .clickInPlace:
            // Electron/Chromium tray items (e.g. Claude) ignore Continuum's synthetic
            // mouse click, so open those via an Accessibility press. Every other
            // app responds to the normal click, which also preserves its native
            // open/close toggle and works with popover-style menus (e.g. Cap,
            // MenuTool) that a stray AX interaction would disturb.
            if MenuBarClickTargetPolicy.shouldAttemptAccessibilityPress(
                mouseButton: mouseButton,
                isElectronItem: isElectronItem(item)
            ), pressItemViaAccessibility(item) {
                MenuBarItemManager.diagLog.info("Activated \(item.logString) via AX press")
                return
            }
            do {
                try await click(item: item, with: mouseButton)
            } catch {
                MenuBarItemManager.diagLog.error("Failed to activate \(item.logString): \(error)")
            }
        case .temporarilyReveal:
            await temporarilyShow(
                item: item,
                clickingWith: mouseButton,
                on: displayID,
                fastPath: fastPath
            )
        }
    }

    /// Activates a menu bar item addressed by its exact runtime identifier.
    ///
    /// This is the mutation-side pair of `currentRuntimeInventory()`: callers
    /// resolve an exact identifier from the snapshot/inventory surface, then
    /// this method admits or rejects the command before touching live CG/AX
    /// state.
    @discardableResult
    func activateItem(
        withIdentifier identifier: String,
        on displayID: CGDirectDisplayID?,
        mouseButton: CGMouseButton = .left,
        fastPath: Bool = false
    ) async -> MenuBarRuntimeCommandPolicy.ActivationDecision {
        let inventory = currentRuntimeInventory()
        guard inventory.item(withIdentifier: identifier) != nil else {
            let decision = MenuBarRuntimeCommandPolicy.activationDecision(
                itemIdentifier: identifier,
                inventory: inventory,
                itemIsOnScreen: false
            )
            if case let .reject(reason) = decision {
                MenuBarItemManager.diagLog.info(
                    "Cannot activate menu bar item; \(reason)"
                )
            }
            return decision
        }

        guard let item = MenuBarRuntimeCommandPolicy.liveItem(
            withIdentifier: identifier,
            in: itemCache
        ) else {
            let reason = MenuBarRuntimeCommandPolicy.RejectionReason
                .liveItemUnavailable(identifier)
            MenuBarItemManager.diagLog.info(
                "Cannot activate menu bar item; \(reason)"
            )
            return .reject(reason)
        }

        let decision = MenuBarRuntimeCommandPolicy.activationDecision(
            itemIdentifier: identifier,
            inventory: inventory,
            itemIsOnScreen: Bridging.isWindowOnScreen(item.windowID)
        )

        switch decision {
        case .allow:
            await activate(
                item: item,
                on: displayID,
                mouseButton: mouseButton,
                fastPath: fastPath
            )
        case let .reject(reason):
            MenuBarItemManager.diagLog.info(
                "Cannot activate menu bar item; \(reason)"
            )
        }

        return decision
    }

    /// Returns whether the item's owning app is an Electron app, detected by the
    /// presence of the bundled Electron framework. Such apps ignore synthetic
    /// mouse clicks on their tray icon and must be opened via an AX press.
    private func isElectronItem(_ item: MenuBarItem) -> Bool {
        // Fall back to ownerPID so this works during startup before sourcePID
        // has been resolved.
        let pid = item.sourcePID ?? item.ownerPID
        guard let bundleURL = NSRunningApplication(processIdentifier: pid)?.bundleURL else {
            return false
        }
        let electronFramework = bundleURL.appendingPathComponent(
            "Contents/Frameworks/Electron Framework.framework"
        )
        return FileManager.default.fileExists(atPath: electronFramework.path)
    }

    private func accessibilityTarget(for item: MenuBarItem) -> UIElement? {
        // Fall back to ownerPID so this works during startup before sourcePID
        // has been resolved.
        let pid = item.sourcePID ?? item.ownerPID
        guard
            let runningApp = NSRunningApplication(processIdentifier: pid),
            let app = AXHelpers.application(for: runningApp),
            let extrasMenuBar = AXHelpers.extrasMenuBar(for: app)
        else {
            return nil
        }

        let children = AXHelpers.children(for: extrasMenuBar)
        let itemBounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
        let candidates = children.enumerated().map { index, child in
            MenuBarAccessibilityPressPolicy.Candidate(
                index: index,
                frame: AXHelpers.frame(for: child)
            )
        }

        switch MenuBarAccessibilityPressPolicy.targetCandidate(
            for: itemBounds,
            candidates: candidates
        ) {
        case .noTarget:
            return nil
        case let .useCandidate(index):
            guard children.indices.contains(index) else {
                return nil
            }
            return children[index]
        }
    }

    /// Attempts to open the item's menu by performing an Accessibility press on
    /// its status item element. Returns false (so the caller can fall back to
    /// a synthetic click) when the element cannot be resolved or the press fails.
    private func pressItemViaAccessibility(_ item: MenuBarItem) -> Bool {
        guard let target = accessibilityTarget(for: item) else {
            return false
        }

        return AXHelpers.press(target)
    }

    private func refreshedClickTarget(
        matching item: MenuBarItem,
        on displayID: CGDirectDisplayID
    ) async -> MenuBarItem {
        let refreshedItems = await MenuBarItem.getMenuBarItems(
            on: displayID,
            option: .onScreen
        )
        return MenuBarClickTargetPolicy.refreshedTarget(
            matching: item,
            in: refreshedItems
        ) ?? item
    }

    /// Clicks a menu bar item with the given mouse button.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    /// Clicks a menu bar item with the given mouse button.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    ///   - skipInputPause: Skip waiting for user input to pause.
    ///   - maxAttempts: Maximum number of click attempts (default 3).
    ///     Pass `1` from `temporarilyShow` so a single failure returns
    ///     immediately and the caller's fallback path fires promptly.
    func click(item: MenuBarItem, with mouseButton: CGMouseButton, skipInputPause: Bool = false, maxAttempts: Int = 3) async throws {
        guard let appState else {
            throw MenuBarEventError.cannotComplete
        }

        _ = try await MenuBarClickExecutor.execute(
            item: item,
            mouseButton: mouseButton,
            skipInputPause: skipInputPause,
            maxAttempts: maxAttempts,
            waitForUserToPauseInput: { try await waitForUserToPauseInput() },
            beginInputSession: { appState.hidEventManager.stopAll() },
            endInputSession: { appState.hidEventManager.startAll() },
            postClickEvents: { item, mouseButton in
                try await postClickEvents(item: item, mouseButton: mouseButton)
            },
            sleepAfterFailedAttempt: { await eventSleep() },
            recordClickStart: { item, mouseButton in
                MenuBarItemManager.diagLog.info(
                    """
                    Clicking \(item.logString) with \
                    \(mouseButton.logString)
                    """
                )
            },
            recordAttemptSuccess: { attempt, clickDuration in
                MenuBarItemManager.diagLog.debug(
                    "Attempt \(attempt) succeeded in \(Int(clickDuration * 1000))ms, finished with click"
                )
            },
            recordAttemptFailure: { attempt, attemptDuration, error in
                MenuBarItemManager.diagLog.debug(
                    "Attempt \(attempt) failed after \(Int(attemptDuration * 1000))ms: \(error)"
                )
            }
        )
    }
}

// MARK: - Temporarily Showing Items

extension MenuBarItemManager {
    /// Waits for a menu bar item's position to stabilize after a move.
    ///
    /// After a Cmd+drag move, the Window Server updates the item's window
    /// position, but the owning app may take additional time to process the
    /// change internally. If we click the item before it has settled, the
    /// app may position its popup at the old location.
    ///
    /// This method polls the item's bounds until two consecutive reads
    /// return the same value, up to a maximum wait time.
    private nonisolated func waitForItemPositionToSettle(item: MenuBarItem) async {
        let maxWait = MenuBarEventPacingPolicy.itemPositionSettleTimeout
        let pollInterval = MenuBarEventPacingPolicy.itemPositionSettlePollInterval
        let startTime = ContinuousClock.now

        var previousBounds = Bridging.getWindowBounds(for: item.windowID)

        while ContinuousClock.now - startTime < maxWait {
            await eventSleep(for: pollInterval)
            let currentBounds = Bridging.getWindowBounds(for: item.windowID)
            switch MenuBarTemporaryRevealPolicy.positionSettleDecision(
                previousBounds: previousBounds,
                currentBounds: currentBounds
            ) {
            case .settled:
                return
            case let .keepWaiting(nextPreviousBounds):
                previousBounds = nextPreviousBounds
            }
        }
    }

    /// Waits until the item's Window Server origin differs from `previousOrigin`,
    /// or until `timeout` elapses.
    ///
    /// Used on the fast path of `temporarilyShow` as a lightweight alternative
    /// to `waitForItemPositionToSettle`: we only need to confirm the Window
    /// Server has applied the new position; we don't need two consecutive
    /// identical readings.
    private nonisolated func waitForItemToLeaveOrigin(
        item: MenuBarItem,
        previousOrigin: CGPoint,
        timeout: Duration
    ) async {
        let pollInterval = MenuBarEventPacingPolicy.revealedItemFastSettlePollInterval
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            await eventSleep(for: pollInterval)
            switch MenuBarTemporaryRevealPolicy.originDepartureDecision(
                previousOrigin: previousOrigin,
                currentOrigin: Bridging.getWindowBounds(for: item.windowID)?.origin
            ) {
            case .departed:
                return
            case .keepWaiting:
                break
            }
        }
    }

    /// Schedules a timer for the given interval that rehides the
    /// temporarily shown items when fired.
    private func runRehideTimer(for interval: TimeInterval? = nil) {
        let interval = interval ?? 15
        MenuBarItemManager.diagLog.debug("Running rehide timer for interval: \(interval)")
        temporaryRevealRuntime.cancelRehideTriggers()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MenuBarItemManager.diagLog.debug("Rehide timer fired")
            Task {
                await self.rehideTemporarilyShownItems()
            }
        }
        temporaryRevealRuntime.attachRehideTimer(timer)
        // Also rehide when frontmost app changes (smart-ish).
        // Debounce so rapid app switches (Cmd-Tab spam) collapse to one
        // rehide attempt instead of queuing a separate Task per change ;
        // each rehide call can do an expensive on-screen window enumeration.
        let cancellable = NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.rehideTemporarilyShownItems()
                }
            }
        temporaryRevealRuntime.attachFrontmostApplicationCancellable(cancellable)
    }

    /// Temporarily moves `item` into the visible area next to the control icon,
    /// clicks it, then schedules a rehide.
    ///
    /// The item is returned to its original location after approximately
    /// 15 seconds, though it may be sooner (e.g. when switching apps) or
    /// later due to the smart rehide logic.
    ///
    /// - Returns: A ``MenuBarTemporaryRevealResult`` describing whether the move and
    ///   click succeeded. Only act on ``MenuBarTemporaryRevealResult/movedButClickFailed``
    ///   for fallback clicks; the item is hidden for every other non-success case.
    @discardableResult
    func temporarilyShow(item: MenuBarItem, clickingWith mouseButton: CGMouseButton, on displayID: CGDirectDisplayID? = nil, fastPath: Bool = false) async -> MenuBarTemporaryRevealResult {
        guard let appState else {
            MenuBarItemManager.diagLog.error("Missing AppState, so not showing \(item.logString)")
            return .showFailed
        }

        let itemBounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
        let resolvedDisplayID = MenuBarDisplayResolutionPolicy.temporaryRevealDisplayID(
            explicitDisplayID: displayID,
            itemBounds: itemBounds,
            screens: NSScreen.screens.map {
                MenuBarDisplayResolutionPolicy.ScreenObservation(
                    displayID: $0.displayID,
                    frame: $0.frame
                )
            },
            activeMenuBarDisplayID: Bridging.getActiveMenuBarDisplayID(),
            mainDisplayID: CGMainDisplayID()
        )

        let originalSection = itemCache.address(for: item.tag)?.section ?? .hidden

        let outcome = await MenuBarTemporaryRevealExecutor.execute(
            item: item,
            mouseButton: mouseButton,
            resolvedDisplayID: resolvedDisplayID,
            originalSection: originalSection,
            fastPath: fastPath,
            operations: MenuBarTemporaryRevealExecutor.Operations(
                hasTemporaryContexts: {
                    !self.temporaryRevealRuntime.isEmpty
                },
                cancelRehideTriggers: {
                    self.temporaryRevealRuntime.cancelRehideTriggers()
                },
                forceRehideExistingContexts: {
                    await self.rehideTemporarilyShownItems(
                        force: true,
                        isCalledFromTemporarilyShow: true
                    )
                },
                outstandingContexts: {
                    self.temporaryRevealRuntime.outstandingContexts
                },
                removeExistingContext: { tag in
                    self.removeTemporarilyShownItemFromCache(with: tag)
                },
                scheduleRehideTimer: {
                    self.runRehideTimer()
                },
                observeItems: { displayID in
                    await MenuBarItem.getMenuBarItems(on: displayID, option: .activeSpace)
                },
                showNoRoomAlert: { item in
                    let alert = NSAlert()
                    alert.messageText = String(
                        localized: "Not enough room to show \"\(item.displayName)\""
                    )
                    alert.runModal()
                },
                recordPendingMetadata: { metadata, tagIdentifier in
                    self.pendingRelocationLedger.record(metadata, for: tagIdentifier)
                },
                clearPendingRelocation: { tagIdentifier in
                    self.pendingRelocationLedger.clear(tagIdentifier: tagIdentifier)
                },
                persistPendingRelocations: {
                    self.persistPendingRelocations()
                },
                beginInputSession: {
                    appState.hidEventManager.stopAll()
                },
                endInputSession: {
                    appState.hidEventManager.startAll()
                },
                windowOrigin: { windowID in
                    Bridging.getWindowBounds(for: windowID)?.origin
                },
                moveItem: { item, destination, displayID, maxMoveAttempts in
                    if let maxMoveAttempts {
                        try await self.move(
                            item: item,
                            to: destination,
                            on: displayID,
                            skipInputPause: true,
                            maxMoveAttempts: maxMoveAttempts
                        )
                    } else {
                        try await self.move(
                            item: item,
                            to: destination,
                            on: displayID,
                            skipInputPause: true
                        )
                    }
                },
                appendContext: { context in
                    self.temporaryRevealRuntime.append(context)
                },
                waitForItemToLeaveOrigin: { item, previousOrigin, timeout in
                    await self.waitForItemToLeaveOrigin(
                        item: item,
                        previousOrigin: previousOrigin,
                        timeout: timeout
                    )
                },
                waitForItemPositionToSettle: { item in
                    await self.waitForItemPositionToSettle(item: item)
                },
                refreshedClickTarget: { item, displayID in
                    await self.refreshedClickTarget(matching: item, on: displayID)
                },
                sleep: { delay in
                    await self.eventSleep(for: delay)
                },
                visibleWindowIDs: {
                    Set(Bridging.getWindowList(option: .onScreen))
                },
                isElectronItem: { item in
                    self.isElectronItem(item)
                },
                pressItemViaAccessibility: { item in
                    self.pressItemViaAccessibility(item)
                },
                clickItem: { item, mouseButton, maxAttempts in
                    try await self.click(
                        item: item,
                        with: mouseButton,
                        skipInputPause: true,
                        maxAttempts: maxAttempts
                    )
                },
                shownInterfaceWindow: { clickPID, idsBeforeClick in
                    WindowInfo.createWindows(option: .onScreen).first { window in
                        window.ownerPID == clickPID &&
                            !idsBeforeClick.contains(window.windowID)
                    }
                }
            ),
            diagnostics: temporaryRevealDiagnostics()
        )
        return outcome.result
    }

    private func temporaryRevealDiagnostics() -> MenuBarTemporaryRevealExecutor.Diagnostics {
        MenuBarTemporaryRevealExecutor.Diagnostics(
            recordStart: { item in
                MenuBarItemManager.diagLog.debug(
                    "temporarilyShow: started for \(item.logString)"
                )
            },
            recordAdmissionBlocked: { stuckTags in
                MenuBarItemManager.diagLog.error(
                    """
                    temporarilyShow: aborting; \(stuckTags.count) item(s) still stuck \
                    after force-rehide: \(stuckTags). \
                    Avoiding further event-gate saturation.
                    """
                )
            },
            recordMissingReturnDestination: { item, displayID in
                MenuBarItemManager.diagLog.error(
                    "No return destination for \(item.logString) on display \(displayID)"
                )
            },
            recordMissingRevealAnchor: { item in
                MenuBarItemManager.diagLog.warning(
                    "Not enough room or no anchor to show \(item.logString)"
                )
            },
            recordRevealMoveStart: { item, displayID in
                MenuBarItemManager.diagLog.debug(
                    "Temporarily showing \(item.logString) on display \(displayID)"
                )
            },
            recordMoveFailure: { _, error in
                MenuBarItemManager.diagLog.error("Error showing item: \(error)")
            },
            recordPreservedPendingMetadata: { item, originalSection in
                MenuBarItemManager.diagLog.warning(
                    """
                    move() threw but item \(item.logString) is no longer in \
                    \(originalSection); preserving pending rehide metadata
                    """
                )
            },
            recordAccessibilityPressSuccess: { item in
                MenuBarItemManager.diagLog.info(
                    "Activated \(item.logString) via AX press"
                )
            },
            recordInitialClickFailure: { _, error in
                MenuBarItemManager.diagLog.error(
                    """
                    Error clicking item (first attempt): \(error); \
                    attempting fallback click
                    """
                )
            },
            recordFallbackClickFailure: { item, error in
                MenuBarItemManager.diagLog.error(
                    "Fallback click also failed for \(item.logString): \(error)"
                )
            }
        )
    }

    /// Resolves the best move destination for returning a temporarily shown
    /// item to its original section.
    ///
    /// Tries destinations in order of preference:
    /// 1. The captured ``MenuBarTemporaryRevealContext/returnDestination``
    ///    (primary neighbor, refreshed with current bounds).
    /// 2. The ``MenuBarTemporaryRevealContext/fallbackNeighborTag`` (the
    ///    neighbor on the opposite side, to preserve relative ordering).
    /// 3. The control item for the item's original section (guarantees
    ///    the item ends up in the correct section, though ordering within
    ///    the section may differ).
    private func resolveReturnDestination(
        for context: MenuBarTemporaryRevealContext,
        in items: [MenuBarItem]
    ) -> MenuBarMoveDestination? {
        guard let resolution = MenuBarTemporaryRevealPolicy.resolveReturnDestination(
            for: context.returnRoute,
            in: items
        ) else {
            MenuBarItemManager.diagLog.error(
                "No return destination found for \(context.tag) in \(context.originalSection.logString)"
            )
            return nil
        }

        if resolution.source == .sectionControl {
            MenuBarItemManager.diagLog.debug(
                """
                Return destination neighbors not found for \(context.tag); \
                falling back to section-level destination for \(context.originalSection.logString)
                """
            )
        }

        return resolution.destination
    }

    /// Rehides all temporarily shown items.
    ///
    /// If an item is currently showing its interface, this method waits
    /// for the interface to close before hiding the items, unless `force`
    /// is `true`, in which case all items are rehidden immediately.
    ///
    /// - Parameter force: If `true`, skip the interface-showing and
    ///   user-input guards and rehide all items immediately.
    func rehideTemporarilyShownItems(force: Bool = false, isCalledFromTemporarilyShow: Bool = false) async {
        guard let appState else {
            MenuBarItemManager.diagLog.error("Missing AppState, so not rehiding")
            return
        }
        guard !temporaryRevealRuntime.isEmpty else {
            return
        }

        _ = await MenuBarTemporaryRehideExecutor.execute(
            force: force,
            isCalledFromTemporarilyShow: isCalledFromTemporarilyShow,
            interfaceIsShowing: force ? false : temporaryRevealRuntime.interfaceIsShowing,
            userInputPaused: force
                ? true
                : hasUserPausedInput(for: MenuBarEventPacingPolicy.rehideUserInputQuietWindow),
            operations: MenuBarTemporaryRehideExecutor.Operations(
                drainContexts: {
                    self.temporaryRevealRuntime.drainContexts()
                },
                restoreContexts: { contexts in
                    self.temporaryRevealRuntime.restoreContexts(contexts)
                },
                observeItems: {
                    await self.observeActiveMenuBarItemsForRuntimeMutation(
                        context: "rehideTemporarilyShownItems"
                    )
                },
                resolveReturnDestination: { context, items in
                    self.resolveReturnDestination(for: context, in: items)
                },
                moveItem: { item, destination, displayID in
                    try await self.move(
                        item: item,
                        to: destination,
                        on: displayID,
                        skipInputPause: true,
                        maxMoveAttempts: 1
                    )
                },
                clearPendingRelocation: { tagIdentifier in
                    self.pendingRelocationLedger.clear(tagIdentifier: tagIdentifier)
                },
                markWaitForRelaunch: { pendingRelocationValue, tagIdentifier in
                    self.pendingRelocationLedger.markWaitForRelaunch(
                        pendingRelocationValue,
                        for: tagIdentifier
                    )
                },
                persistPendingRelocations: {
                    self.persistPendingRelocations()
                },
                appendFailedContextsForRetry: { contexts in
                    self.temporaryRevealRuntime.appendFailedContextsForRetry(contexts)
                },
                scheduleRehideTimer: { delay in
                    self.runRehideTimer(for: delay)
                },
                beginInputSession: {
                    appState.hidEventManager.stopAll()
                },
                endInputSession: {
                    appState.hidEventManager.startAll()
                },
                hideCursor: {
                    MouseHelpers.hideCursor()
                },
                showCursor: {
                    MouseHelpers.showCursor()
                },
                sleepBeforeRehide: { delay in
                    await self.eventSleep(for: delay)
                }
            ),
            diagnostics: temporaryRehideDiagnostics()
        )
    }

    private func temporaryRehideDiagnostics() -> MenuBarTemporaryRehideExecutor.Diagnostics {
        MenuBarTemporaryRehideExecutor.Diagnostics(
            recordStart: { force, isCalledFromTemporarilyShow in
                MenuBarItemManager.diagLog.debug(
                    """
                    rehideTemporarilyShownItems: started \
                    (force=\(force), \
                    isCalledFromTemporarilyShow=\(isCalledFromTemporarilyShow))
                    """
                )
            },
            recordDeferral: { reason in
                switch reason {
                case .interfaceShowing:
                    MenuBarItemManager.diagLog.debug(
                        "Menu bar item interface is shown, so waiting to rehide"
                    )
                case .recentUserInput:
                    MenuBarItemManager.diagLog.debug(
                        "Found recent user input, so waiting to rehide"
                    )
                }
            },
            recordRehideStart: {
                MenuBarItemManager.diagLog.debug("Rehiding temporarily shown items")
            },
            recordMissingItem: { context in
                MenuBarItemManager.diagLog.debug(
                    """
                    Missing temporarily shown item \(context.tag) on active space \
                    (not-found attempt \(context.notFoundAttempts)); will retry
                    """
                )
            },
            recordMissingItemHandOff: { context in
                MenuBarItemManager.diagLog.warning(
                    """
                    Giving up in-memory retry for \(context.tag) after \
                    \(context.notFoundAttempts) not-found attempts; \
                    pendingRelocations will handle recovery
                    """
                )
            },
            recordMissingDestination: { _, item in
                MenuBarItemManager.diagLog.error(
                    """
                    Could not resolve return destination for \(item.logString); \
                    item will remain in visible section until next cache cycle \
                    handles pendingRelocations
                    """
                )
            },
            recordMoveFailure: { context, item, error in
                MenuBarItemManager.diagLog.warning(
                    """
                    Attempt \(context.rehideAttempts) to rehide \
                    \(item.logString) failed with error: \
                    \(error)
                    """
                )
            },
            recordWaitForRelaunch: { context, item in
                MenuBarItemManager.diagLog.error(
                    """
                    Giving up rehide for \(item.logString) after \
                    \(context.rehideAttempts) total attempts; \
                    marked waitForRelaunch; relocatePendingItems will \
                    retry only after app relaunch (new windowID)
                    """
                )
            },
            recordAllSucceeded: {
                MenuBarItemManager.diagLog.debug("All items were successfully rehidden")
            },
            recordFailedContexts: { contexts in
                MenuBarItemManager.diagLog.error(
                    """
                    Some items failed to rehide; keeping in context for retry: \
                    \(contexts.map(\.tag))
                    """
                )
            }
        )
    }

    /// Removes a temporarily shown item from the cache, ensuring that
    /// the item is _not_ returned to its original location.
    func removeTemporarilyShownItemFromCache(with tag: MenuBarItemTag) {
        for _ in temporaryRevealRuntime.removeContexts(matching: tag) {
            MenuBarItemManager.diagLog.debug(
                """
                Removing temporarily shown item from cache: \
                \(tag)
                """
            )
        }
        // Also clear any pending relocation since the user explicitly
        // placed the item in a new position.
        let tagIdentifier = tag.tagIdentifier
        if pendingRelocationLedger.clear(tagIdentifier: tagIdentifier) {
            persistPendingRelocations()
        }
    }
}

// MARK: - Control Item Order

extension MenuBarItemManager {
    /// Relocates any newly appearing items that macOS placed to the left
    /// of our control items back into the visible section.
    ///
    /// Returns true if a relocation was performed.
    private func relocateNewLeftmostItems(
        _ items: [MenuBarItem],
        controlItems: MenuBarControlItems,
        previousWindowIDs: [CGWindowID]
    ) async -> Bool {
        guard appState != nil else { return false }

        if knownItemLedger.consumeRelocationSuppressionAndSeed(from: items) {
            // Seed known identifiers so these baseline items won't be treated as "new"
            // on subsequent cache passes, then clear the suppression flag.
            // Skip items without stable identity so Control Center placeholders
            // never enter the persisted set.
            persistKnownItemIdentifiers()
            return false
        }

        // During startup settling, the first cache pass may have items tagged
        // with wrong namespaces (e.g. com.apple.controlcenter when sourcePID
        // hasn't resolved yet). Using those wrong tags to build hiddenTags /
        // alwaysHiddenTags causes ALL items to appear as "new" on the next
        // pass with correct sourcePIDs, triggering a destructive relocation
        // cascade that moves every hidden/always-hidden item to visible.
        // Seed identifiers and skip relocation; the settling-end restore pass
        // will handle correct placement.
        if startupSettlingRuntime.isActive {
            // Skip items without stable identity so Control Center placeholders
            // never enter the persisted set.
            if knownItemLedger.seedPersistableIdentifiers(from: items) {
                persistKnownItemIdentifiers()
            }
            return false
        }

        // Cached hidden / always-hidden tags from the prior cache cycle.
        // The planner uses these to short-circuit re-relocating items
        // already placed in a hidden section.
        let hiddenTags = Set(itemCache[.hidden].map(\.tag))
        let alwaysHiddenTags = Set(itemCache[.alwaysHidden].map(\.tag))

        // Pre-compute live state for the planner. hiddenBounds and the
        // section classification both require the live Window Server;
        // computing them here keeps planLeftmostMove pure over its inputs.
        let hiddenBounds = bestBounds(for: controlItems.hidden)
        let sectionContext = sectionLookupContext(for: controlItems)
        var sectionByWindowID = [CGWindowID: MenuBarSection.Name]()
        for item in items {
            if let section = sectionContext.findSection(for: item) {
                sectionByWindowID[item.windowID] = section
            }
        }

        let decision = LayoutSolver.planLeftmostMove(
            items: items,
            observation: LayoutSolver.LeftmostObservation(
                hiddenBounds: hiddenBounds,
                sectionByWindowID: sectionByWindowID,
                previousWindowIDs: previousWindowIDs
            ),
            savedSectionOrder: savedSectionOrder,
            knownItemIdentifiers: knownItemLedger.identifiers,
            hiddenTags: hiddenTags,
            alwaysHiddenTags: alwaysHiddenTags,
            effectiveNewItemsSection: effectiveNewItemsSection
        )

        switch decision {
        case let .controlIcon(controlIcon):
            MenuBarItemManager.diagLog.info("Relocating Continuum icon \(controlIcon.logString) to visible section")
            do {
                try await move(
                    item: controlIcon,
                    to: .rightOfItem(controlItems.hidden),
                    skipInputPause: true
                )
            } catch {
                MenuBarItemManager.diagLog.error("Failed to relocate Continuum icon \(controlIcon.logString): \(error)")
                return false
            }
            return true

        case let .systemItem(systemItem):
            MenuBarItemManager.diagLog.info("Relocating non-hideable system item \(systemItem.logString) to visible section")
            do {
                try await move(
                    item: systemItem,
                    to: .rightOfItem(controlItems.hidden),
                    skipInputPause: true
                )
            } catch {
                MenuBarItemManager.diagLog.error("Failed to relocate system item \(systemItem.logString): \(error)")
                return false
            }
            return true

        case let .newHideableItem(candidate, identifierToMark):
            // Track this item so future cache cycles don't treat it as new.
            if knownItemLedger.remember(identifierToMark) {
                persistKnownItemIdentifiers()
            }

            let destination = newItemsMoveDestination(for: controlItems, among: items)

            MenuBarItemManager.diagLog.info(
                "Relocating new item \(candidate.logString) to \(effectiveNewItemsSection.logString)"
            )

            // Skip items with no valid bounds (transient clone windows
            // etc.). This live check stays in the orchestrator because
            // it requires Bridging.
            guard Bridging.getWindowBounds(for: candidate.windowID) != nil else {
                MenuBarItemManager.diagLog.warning("Skipping relocation for \(candidate.logString); no valid bounds, likely transient")
                return false
            }

            do {
                try await move(
                    item: candidate,
                    to: destination,
                    skipInputPause: true
                )
            } catch {
                MenuBarItemManager.diagLog.error("Failed to relocate \(candidate.logString): \(error)")
                return false
            }
            return true

        case let .noop(reason):
            switch reason {
            case .unresolvedSourcePID:
                MenuBarItemManager.diagLog.debug(
                    "relocateNewLeftmostItems: skipping, hideable items have unresolved sourcePIDs"
                )
            case .alreadyInTarget:
                MenuBarItemManager.diagLog.debug(
                    "relocateNewLeftmostItems: candidate already in \(effectiveNewItemsSection.logString), skipping"
                )
            case .noNewCandidate, .noLeftmostItems:
                break
            }
            return false
        }
    }

    /// Relocates items whose apps quit while they were temporarily shown
    /// in the visible section back to their original section.
    ///
    /// When `temporarilyShow` moves an item to the visible section, macOS
    /// persists that position. If the app quits before rehide can move it
    /// back, the icon will reappear in the visible section on relaunch.
    /// This method checks for such items and moves them back.
    ///
    /// Returns `true` if any items were relocated.
    private func relocatePendingItems(
        _ items: [MenuBarItem],
        controlItems: MenuBarControlItems
    ) async -> Bool {
        guard !pendingRelocationLedger.isEmpty else {
            return false
        }

        let planningInput = pendingRelocationLedger.relocationPlanningInput(
            contexts: temporaryRevealRuntime.relocationPlanningContexts
        )

        let hiddenBounds = bestBounds(for: controlItems.hidden)

        // Pre-compute live per-item bounds for the planner's "already in
        // hidden section" comparison. Done here so the planner stays pure
        // over its inputs (no Bridging calls inside).
        let boundsForWindowID = PendingLedger.boundsByWindowID(items: items) { item in
            bestBounds(for: item)
        }

        let outcome = await MenuBarPendingRelocationExecutor.execute(
            tagIdentifiers: pendingRelocationLedger.tagIdentifiers,
            items: items,
            controlItems: controlItems,
            hiddenBounds: hiddenBounds,
            boundsForWindowID: boundsForWindowID,
            planningInput: planningInput,
            operations: MenuBarPendingRelocationExecutor.Operations(
                pendingEntry: { tagIdentifier in
                    self.pendingRelocationLedger.pendingEntry(for: tagIdentifier)
                },
                clearEntry: { tagIdentifier in
                    self.pendingRelocationLedger.clear(tagIdentifier: tagIdentifier)
                },
                promoteWaitForRelaunch: { tagIdentifier, promotedSection in
                    self.pendingRelocationLedger.promoteWaitForRelaunch(
                        for: tagIdentifier,
                        to: promotedSection
                    )
                },
                persistPendingRelocations: {
                    self.persistPendingRelocations()
                },
                moveItem: { item, destination in
                    try await self.move(item: item, to: destination, skipInputPause: true)
                }
            ),
            diagnostics: pendingRelocationDiagnostics()
        )
        return outcome.didRelocate
    }

    private func pendingRelocationDiagnostics() -> MenuBarPendingRelocationExecutor.Diagnostics {
        MenuBarPendingRelocationExecutor.Diagnostics(
            recordWaitForRelaunchPromotion: { item in
                MenuBarItemManager.diagLog.info(
                    """
                    relocatePendingItems: \(item.logString) has new windowID; \
                    clearing waitForRelaunch sentinel
                    """
                )
            },
            recordMoveStart: { item, targetSection in
                MenuBarItemManager.diagLog.info(
                    """
                    Relocating \(item.logString) back to \
                    \(targetSection.logString) after app relaunch
                    """
                )
            },
            recordMoveFailure: { item, targetSection, error in
                MenuBarItemManager.diagLog.error(
                    """
                    Failed to relocate \(item.logString) back to \
                    \(targetSection.logString): \(error)
                    """
                )
            },
            recordWaitForRelaunchActive: { item in
                MenuBarItemManager.diagLog.debug(
                    """
                    relocatePendingItems: skipping \(item.logString); \
                    waitForRelaunch sentinel active (same windowID)
                    """
                )
            }
        )
    }

    /// Returns the best-known bounds for a menu bar item.
    private func bestBounds(for item: MenuBarItem) -> CGRect {
        Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
    }

    /// Builds a live section lookup context for the current Window Server state.
    private func sectionLookupContext(for controlItems: MenuBarControlItems) -> MenuBarSectionLookupContext {
        MenuBarSectionLookupContext(
            controlItems: controlItems,
            currentBoundsForItem: { Bridging.getWindowBounds(for: $0.windowID) }
        )
    }

    /// Enforces the order of the given control items, ensuring that the
    /// control item for the always-hidden section is positioned to the
    /// left of control item for the hidden section.
    private func enforceControlItemOrder(controlItems: MenuBarControlItems) async {
        guard
            let alwaysHidden = controlItems.alwaysHidden,
            let destination = MenuBarControlItemOrderPolicy.correctionDestination(
                for: controlItems
            )
        else {
            return
        }

        do {
            MenuBarItemManager.diagLog.debug("Control items have incorrect order")
            try await move(item: alwaysHidden, to: destination, skipInputPause: true)
        } catch {
            MenuBarItemManager.diagLog.error("Error enforcing control item order: \(error)")
        }
    }

    /// Returns a Boolean value that indicates whether any menu bar item
    /// currently has a menu open.
    func isAnyMenuBarItemMenuOpen() async -> Bool {
        if menuOpenProbeRuntime.cachedResultDecision() == .useCachedOpenMenu {
            MenuBarItemManager.diagLog.debug("Menu open check: using cached result true")
            return true
        }

        if let existingTask = menuOpenProbeRuntime.currentTask {
            MenuBarItemManager.diagLog.debug("Menu open check: joining in-flight probe")
            return await existingTask.value
        }

        let cachedItems = itemCache.managedItems.filter(\.isOnScreen)

        let task = Task.detached(priority: .utility) { () -> Bool in
            await MenuBarMenuOpenProbeExecutor.probe(cachedItems: cachedItems)
        }

        menuOpenProbeRuntime.start(task)
        let result = await task.value
        menuOpenProbeRuntime.finish(result: result)
        return result
    }
}

// MARK: Layout Reset

extension MenuBarItemManager {
    /// Resets menu bar layout data to a fresh-install state and moves all
    /// movable, hideable items (except the Continuum icon) to the
    /// Hidden section.
    ///
    /// - Returns: The number of items that failed to move.
    func resetLayoutToFreshState() async throws -> Int {
        MenuBarItemManager.diagLog.info("Resetting menu bar layout to fresh state")
        // A user-initiated reset is authoritative: end the startup settling period
        // immediately so that the post-reset cache is not blocked from running restore
        // and saveSectionOrder by an in-flight settling task.
        startupSettlingRuntime.cancelSettling()
        layoutMutationState.beginReset()
        defer { layoutMutationState.endReset() }

        guard let appState else {
            throw MenuBarLayoutResetError.missingAppState
        }

        // Reset persisted state so macOS treats section dividers like new.
        ControlItemDefaults[.preferredPosition, ControlItem.Identifier.visible.rawValue] = 0
        ControlItemDefaults.resetChevronPositions()

        // Forget previously seen items so we treat everything as new.
        knownItemLedger.clearIdentifiers()
        pendingRelocationLedger.clearAll()
        savedSectionOrderLedger.clear()

        persistKnownItemIdentifiers()
        persistPendingRelocations()
        persistSavedSectionOrder()
        temporaryRevealRuntime.clearContexts()

        // Reset new items placement to default.
        newItemsPlacement = MenuBarNewItemsPlacementPreference.defaultPlacement
        Defaults.removeObject(forKey: .newItemsSection)
        Defaults.removeObject(forKey: .newItemsPlacementData)

        // Prevent the first post-reset cache pass from treating the freshly reset items as "new".
        knownItemLedger.armNextNewLeftmostItemRelocationSuppression()

        appState.menuBarManager.overlayTrayPanel.close()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        let outcome = await MenuBarLayoutResetExecutor.execute(
            alwaysHiddenSectionEnabled: appState.settings.advanced.enableAlwaysHiddenSection,
            controlItemWindowIDs: resolvedControlItemWindowIDs(),
            operations: MenuBarLayoutResetExecutor.Operations(
                observeItems: { context in
                    await self.observeActiveMenuBarItemsForRuntimeMutation(context: context)
                },
                setAlwaysHiddenSectionEnabled: { isEnabled in
                    appState.settings.advanced.enableAlwaysHiddenSection = isEnabled
                },
                enforceControlItemOrder: { controlItems in
                    await self.enforceControlItemOrder(controlItems: controlItems)
                },
                moveItem: { item, destination in
                    try await self.move(
                        item: item,
                        to: destination,
                        skipInputPause: true,
                        watchdogTimeout: Self.layoutWatchdogTimeout
                    )
                },
                boundsForItem: { item in
                    Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
                },
                sleep: { duration in
                    try? await Task.sleep(for: duration)
                }
            ),
            diagnostics: layoutResetDiagnostics()
        )

        guard outcome.stopReason == .completed else {
            throw MenuBarLayoutResetError.missingControlItems
        }

        return try await finishLayoutResetAfterMovePasses(failedMoves: outcome.failedMoveCount)
    }

    private func finishLayoutResetAfterMovePasses(failedMoves: Int) async throws -> Int {
        guard let appState else {
            throw MenuBarLayoutResetError.missingAppState
        }

        _ = await MenuBarLayoutResetFinalizer.execute(
            operations: MenuBarLayoutResetFinalizer.Operations(
                clearCacheLedger: {
                    self.cacheRuntime.clearLedger()
                },
                resetItemCache: {
                    self.itemCache = MenuBarItemCache(displayID: nil)
                },
                storeBackgroundContinuation: { continuation in
                    self.cacheRuntime.storeBackgroundContinuation(continuation)
                },
                startCacheRebuild: {
                    Task { @MainActor in
                        await self.cacheItemsRegardless(skipRecentMoveCheck: true)
                    }
                },
                clearNewItemSuppression: {
                    self.knownItemLedger.clearNextNewLeftmostItemRelocationSuppression()
                },
                clearImageCache: {
                    appState.imageCache.clearAll()
                },
                cleanupImageCache: {
                    appState.imageCache.performCacheCleanup()
                },
                itemCacheHasDisplayID: {
                    self.itemCache.displayID != nil
                },
                updateImageCache: {
                    await appState.imageCache.updateCacheWithoutChecks(
                        sections: MenuBarSection.Name.allCases
                    )
                },
                sleep: { duration in
                    try? await Task.sleep(for: duration)
                },
                publishChange: {
                    appState.objectWillChange.send()
                },
                invalidateMenuBarHeightCache: {
                    // Clear any stale -1 sentinel that may have been written into
                    // menuBarHeightCache while the Menubar window was transiently
                    // unavailable during the reset. The item cache is fully rebuilt
                    // at this point, so the next mouse event will perform a fresh
                    // live lookup and cache the correct height.
                    NSScreen.invalidateMenuBarHeightCache()
                }
            )
        )

        return failedMoves
    }

    private func layoutResetDiagnostics() -> MenuBarLayoutResetExecutor.Diagnostics {
        MenuBarLayoutResetExecutor.Diagnostics(
            recordMissingControlItems: {
                MenuBarItemManager.diagLog.error(
                    "Layout reset aborted: missing hidden section control item"
                )
            },
            recordControlRecoverySuccess: {
                MenuBarItemManager.diagLog.info(
                    """
                    Recovered hidden section control item after \
                    re-enabling always-hidden section
                    """
                )
            },
            recordSecondPassStart: { count in
                MenuBarItemManager.diagLog.debug(
                    "Layout reset pass 2: \(count) items not yet in hidden section"
                )
            },
            recordMoveFailure: { item, error in
                MenuBarItemManager.diagLog.error(
                    "Failed to move \(item.logString) during layout reset: \(error)"
                )
            }
        )
    }

    /// Wrapper for UI callers; kept separate for clarity in call sites.
    @MainActor
    func resetLayoutFromSettingsPane() async throws -> Int {
        try await resetLayoutToFreshState()
    }

    /// Awaits the end of the startup settling window before returning.
    ///
    /// Loops in case performSetup re-enters mid-await (e.g. a permission
    /// re-grant during login): re-entry cancels the captured task and
    /// starts a new settling window, so resuming on a single captured
    /// task could land back inside an active window. Re-check the startup
    /// runtime after each await and pick up the current settling task.
    private func waitForStartupSettlingToEnd() async {
        while startupSettlingRuntime.isActive {
            guard let settlingTask = startupSettlingRuntime.currentSettlingTask else { break }
            MenuBarItemManager.diagLog.debug(
                "applySavedSectionLayout: waiting for startup settling to end"
            )
            await settlingTask.value
        }
    }

    /// Applies the saved section layout by moving items to match persisted
    /// section assignments and within-section ordering.
    ///
    /// Uses per-item identifiers (not just bundle IDs) to correctly handle
    /// apps like Control Center that share a single bundle ID across many
    /// items (WiFi, Battery, etc.).
    ///
    /// The approach processes each section's saved item order and moves items
    /// into position one at a time, achieving both correct section placement
    /// and correct ordering in a single pass.
    /// Schedules the post-apply refresh sequence on a detached Task:
    /// a full cache cycle (which updates itemCache, re-runs the
    /// relocate paths and persists savedSectionOrder if appropriate),
    /// then imageCache cleanup and an observer notification.
    ///
    /// applySavedSectionLayout's exit points (Phase 7 normal exit plus the
    /// Phase 6 early-returns) cannot inline-await cacheItemsRegardless
    /// because they're inside a body that the outer cacheItemsRegardless
    /// is awaiting via applySavedLayout. The outer call holds the cache
    /// runtime's serial gate across that await, so an inline recursive call
    /// is rejected with "serial cache operation already in progress,
    /// skipping" and itemCache stays stale (the field-reported symptom:
    /// quit apps still appear in Settings Layout and OverlayTray
    /// until something else triggers a non-applySavedLayout cache
    /// cycle). Spawning a Task defers execution until after the outer
    /// releases the gate, mirroring the relocate-path recache pattern.
    /// The uiSettleDelay gives WindowServer a tick to settle the moves
    /// (or, for early-returns, the windowID churn that triggered the
    /// apply) before the next snapshot.
    private func scheduleDeferredCacheRefresh() {
        let scheduleDecision = deferredCacheRefreshRuntime.schedule()
        let token: MenuBarDeferredCacheRefreshRuntime.Token
        switch scheduleDecision {
        case .alreadyScheduled:
            MenuBarItemManager.diagLog.debug(
                "deferred cache refresh already scheduled; coalescing request"
            )
            return
        case let .schedule(scheduledToken):
            token = scheduledToken
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.deferredCacheRefreshRuntime.finish(token)
            }

            do {
                try await Task.sleep(for: MenuBarItemManager.uiSettleDelay)
            } catch is CancellationError {
                return
            } catch {
                return
            }

            // skipSavedLayoutApply=true breaks the dispatch loop: the
            // apply already ran (we're scheduling a refresh after it);
            // re-entering applySavedLayout here would re-trigger on
            // any transient windowID-set churn and live-lock the bar.
            // Cache update + save still run via uncheckedCacheItems.
            await self.cacheItemsRegardless(
                skipRecentMoveCheck: true,
                skipSavedLayoutApply: true
            )
            guard let appState = self.appState else { return }
            appState.imageCache.performCacheCleanup()
            await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
            await MainActor.run { appState.objectWillChange.send() }
        }
        deferredCacheRefreshRuntime.attachTask(task, for: token)
    }

    private func observeActiveMenuBarItemsForRuntimeMutation(context: String) async -> [MenuBarItem]? {
        switch await MenuBarObservationRuntime.observe(
            displayID: Bridging.getActiveMenuBarDisplayID(),
            resolveSourcePID: true,
            itemProvider: { resolveSourcePID in
                await MenuBarItem.getMenuBarItems(
                    option: .activeSpace,
                    resolveSourcePID: resolveSourcePID
                )
            }
        ) {
        case let .observed(result):
            if result.observation.cloneCount > 0 {
                MenuBarItemManager.diagLog.debug(
                    "runtimeObservation[\(context)]: dropping \(result.observation.cloneCount) system clone window(s): \(result.observation.droppedCloneDescriptions)"
                )
                diagnosticsRuntime.recordCloneWindowsDropped(result.observation.cloneCount)
            }
            return result.items
        case let .zeroItems(failure):
            MenuBarItemManager.diagLog.error(
                "runtimeObservation[\(context)]: \(failure.detail) after \(failure.attempts) attempt(s); deferring refresh"
            )
            recordZeroItemObservation(detail: failure.detail)
            return nil
        }
    }

    func applySavedSectionLayout(
        itemSectionMap: [String: String],
        itemOrder: [String: [String]]
    ) async {
        // MARK: Phase 0: gate on startup settling

        //
        await waitForStartupSettlingToEnd()

        // Bail before arming layout state if cancellation arrived during
        // the settling wait.
        if Task.isCancelled { return }

        // Prevent the cache cycle from saving intermediate positions.
        // The apply moves items in flight, and saveSectionOrder must not
        // capture those intermediate states.
        layoutMutationState.beginSavedLayoutRestore()
        defer {
            layoutMutationState.endSavedLayoutRestore()
        }

        guard let appState else {
            MenuBarItemManager.diagLog.error("applySavedSectionLayout: missing appState")
            return
        }
        guard !itemOrder.isEmpty else {
            MenuBarItemManager.diagLog.debug("applySavedSectionLayout: no item order, skipping")
            return
        }

        // MARK: Phase 2: discover items, classify sections, build sequences

        let controlItemWindowIDs = resolvedControlItemWindowIDs()

        guard let observedItems = await observeActiveMenuBarItemsForRuntimeMutation(context: "initial") else {
            scheduleDeferredCacheRefresh()
            return
        }
        guard let observationSnapshot = MenuBarSavedLayoutObservationSnapshot(
            observedItems: observedItems,
            controlItemWindowIDs: controlItemWindowIDs,
            itemSectionMap: itemSectionMap,
            itemOrder: itemOrder,
            makeSectionLookupContext: { sectionLookupContext(for: $0) }
        ) else {
            MenuBarItemManager.diagLog.error("applySavedSectionLayout: missing control items")
            return
        }

        let activeScreen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main
        let preparation = MenuBarSavedLayoutPreparation.prepare(
            observationSnapshot: observationSnapshot,
            savedSectionOrder: savedSectionOrder,
            newItemsPlacement: newItemsPlacement,
            settings: MenuBarSavedLayoutPreparation.Settings(
                enableMenuBarItemOverflow: appState.settings.advanced.enableMenuBarItemOverflow,
                useLCSOnNotchedDisplay: appState.settings.advanced.useLCSSortingOnNotchedDisplays
            ),
            screen: activeScreen.map { screen in
                MenuBarSavedLayoutPreparation.ScreenObservation(
                    frame: screen.frame,
                    hasNotch: screen.hasNotch,
                    notchFrame: screen.frameOfNotch
                )
            },
            notchGap: MenuBarSection.notchGap
        )

        let items = preparation.items
        let controlItems = preparation.controlItems
        let hiddenCtrlUID = preparation.hiddenControlUID
        let ahCtrlUID = preparation.alwaysHiddenControlUID
        let sectionByWindowID = preparation.sectionByWindowID
        let currentFlat = preparation.currentFlat
        let desiredFiltered = preparation.desiredFiltered
        let sectionMap = preparation.sectionMap

        for sectionName in [MenuBarSection.Name.visible, .hidden, .alwaysHidden] {
            let sectionItems = preparation.sectionUIDs[sectionName] ?? []
            MenuBarItemManager.diagLog.debug(
                "applySavedSectionLayout: current \(sectionName.logString) has \(sectionItems.count) items: \(sectionItems)"
            )
        }

        // MARK: Phase 3: place unmanaged items via planUnmanagedPlacement

        let unmanagedPlan = preparation.unmanagedPlan
        let unmanagedUIDs = unmanagedPlan.unmanagedUIDs
        if unmanagedPlan.hasUnmanagedItems {

            // Per-uid decision trace. Shows which item was deemed
            // unmanaged and which placement strategy fired. Cheap
            // (only logs when unmanaged items exist) and the most
            // direct signal for triaging "why did X move?" reports.
            for uid in unmanagedUIDs {
                MenuBarItemManager.diagLog.debug(
                    "Saved layout: planUnmanagedPlacement \(uid) -> \(unmanagedPlan.placementSummary(for: uid))"
                )
            }

            MenuBarItemManager.diagLog.debug(
                "Saved layout: \(unmanagedUIDs.count) unmanaged item(s) placed via planUnmanagedPlacement"
            )
        }

        // MARK: Phase 4: notch overflow rebalance

        if let notchOverflow = preparation.notchOverflow {
            let budget = notchOverflow.budget
            MenuBarItemManager.diagLog.debug(
                """
                Notch overflow budget: screen.maxX=\(activeScreen?.frame.maxX ?? 0) \
                notch=[\(activeScreen?.frameOfNotch?.minX ?? 0)…\(activeScreen?.frameOfNotch?.maxX ?? 0)] \
                rightBoundary=\(budget.rightBoundary) availableWidth=\(budget.availableWidth) \
                visibleUIDs.count=\(budget.visibleUIDs.count) \
                nonLayoutCount=\(budget.nonLayoutCount) nonLayoutFootprint=\(budget.nonLayoutFootprint) \
                chevronFootprint=\(budget.chevronFootprint) \
                nonLayoutBreakdown=[\(budget.nonLayoutBreakdown.joined(separator: ", "))]
                """
            )

            if !notchOverflow.result.overflowUIDs.isEmpty {
                MenuBarItemManager.diagLog.info(
                    "Saved layout: notch overflow; \(notchOverflow.result.overflowUIDs.count) item(s) moved from visible to hidden"
                )
            }
        }

        // MARK: Phase 5: choose execution strategy (full-sort vs LCS)

        let executionPlan = preparation.executionPlan
        if executionPlan == .alreadyMatches {
            MenuBarItemManager.diagLog.info("Saved layout: current order already matches desired, skipping")
            scheduleDeferredCacheRefresh()
            return
        }

        let cursorSession = MenuBarSavedLayoutCursorSession.begin(
            mouseLocation: NSEvent.mouseLocation,
            hideCursor: { MouseHelpers.hideCursor(watchdogTimeout: $0) },
            beginSuppression: { syntheticEventRuntime.beginCursorManagementSuppression() }
        )
        defer {
            cursorSession.finish(
                screenFrames: NSScreen.screens.map(\.frame),
                fallbackScreenFrame: NSScreen.main?.frame,
                endSuppression: { syntheticEventRuntime.endCursorManagementSuppression() },
                warpCursor: { MouseHelpers.warpCursor(to: $0) },
                showCursor: { MouseHelpers.showCursor() }
            )
        }

        switch executionPlan {
        case .alreadyMatches:
            scheduleDeferredCacheRefresh()
            return
        case let .fullSort(fullSequence):
            // MARK: Phase 6a: full-sort execution (notched)

            let hiddenCtrlUID = controlItems.hidden.uniqueIdentifier
            let ahCtrlUID = controlItems.alwaysHidden?.uniqueIdentifier

            MenuBarItemManager.diagLog.info(
                "Saved layout (full sort): \(fullSequence.count) item(s) including controls"
            )
            MenuBarItemManager.diagLog.debug(
                "Saved layout (full sort): sequence = \(fullSequence)"
            )

            let fullSortOutcome = await MenuBarSavedLayoutFullSortExecutor.execute(
                sequence: fullSequence,
                hiddenControlUID: hiddenCtrlUID,
                alwaysHiddenControlUID: ahCtrlUID,
                observationContext: "fullSortMove",
                observeItems: { await observeActiveMenuBarItemsForRuntimeMutation(context: $0) },
                moveItem: { item, destination in
                    try await move(item: item, to: destination, skipInputPause: true)
                },
                recordItemMissing: { uid in
                    MenuBarItemManager.diagLog.debug("Saved layout (full sort): \(uid) not found, skipping")
                },
                recordControlCenterMissing: {
                    MenuBarItemManager.diagLog.error("Saved layout (full sort): Control Center not found")
                },
                recordMoveStart: { uid, _ in
                    MenuBarItemManager.diagLog.debug("Saved layout (full sort): \(uid) → .leftOfItem(CC)")
                },
                recordMoveFailure: { uid, error in
                    MenuBarItemManager.diagLog.error("Saved layout (full sort): failed \(uid): \(error)")
                }
            )
            if fullSortOutcome.needsDeferredCacheRefresh {
                scheduleDeferredCacheRefresh()
                return
            }

            MenuBarItemManager.diagLog.info("Saved layout (full sort): completed with \(fullSortOutcome.movedCount) move(s)")

            // Give macOS a moment to finalize positions before restoring
            // control item widths.
            try? await Task.sleep(
                for: MenuBarSavedLayoutExecutionPolicy.delay(after: .fullSortSettle)
            )

            // Restore control items to their normal hiding state. The
            // control items are now at their correct positions between
            // sections, so expanding them to 10000px will push items to
            // their left off-screen, effectively hiding them.
            for section in appState.menuBarManager.sections {
                section.desiredState = .hideSection
                section.controlItem.state = .hideSection
            }

            // Give macOS time to process the control item expansion.
            try? await Task.sleep(
                for: MenuBarSavedLayoutExecutionPolicy.delay(after: .controlExpansionSettle)
            )
        case .lcs:
            // MARK: Phase 6b: LCS execution (non-notched)

            let lcsOutcome = await MenuBarSavedLayoutLCSExecutor.execute(
                currentFlat: currentFlat,
                items: items,
                sectionByWindowID: sectionByWindowID,
                desiredFiltered: desiredFiltered,
                sectionMap: sectionMap,
                itemOrder: itemOrder,
                hiddenControlUID: hiddenCtrlUID,
                alwaysHiddenControlUID: ahCtrlUID,
                controlItemWindowIDs: controlItemWindowIDs,
                observeItems: { await observeActiveMenuBarItemsForRuntimeMutation(context: $0) },
                makeSectionLookupContext: { sectionLookupContext(for: $0) },
                moveItem: { item, destination in
                    try await move(item: item, to: destination, skipInputPause: true)
                },
                recordVisibleBoundaryMovesNeeded: { count in
                    MenuBarItemManager.diagLog.info(
                        "Saved layout: \(count) visible/tray boundary move(s) needed"
                    )
                },
                recordVisibleBoundaryMoveFailure: { uid, error in
                    MenuBarItemManager.diagLog.error(
                        "Saved layout: visible/tray boundary move failed for \(uid): \(error)"
                    )
                },
                recordRefreshControlItemsMissing: { context in
                    MenuBarItemManager.diagLog.error(
                        "applySavedSectionLayout: lost control items during \(context)"
                    )
                },
                recordTransitionAssessment: { transitionAssessment in
                    MenuBarItemManager.diagLog.debug(
                        "Saved layout Phase 1: ahCtrlUID=\(ahCtrlUID ?? "nil"), crossSectionMoves=\(transitionAssessment.crossSectionMoveCount), totalSectionMismatch=\(transitionAssessment.totalSectionMismatch)"
                    )
                    MenuBarItemManager.diagLog.debug(
                        "Saved layout Phase 1: currentHidden=\(transitionAssessment.sets.currentHidden.sorted())"
                    )
                    MenuBarItemManager.diagLog.debug(
                        "Saved layout Phase 1: currentAH=\(transitionAssessment.sets.currentAlwaysHidden.sorted())"
                    )
                    MenuBarItemManager.diagLog.debug(
                        "Saved layout Phase 1: desiredHidden=\(transitionAssessment.sets.desiredHidden.sorted())"
                    )
                    MenuBarItemManager.diagLog.debug(
                        "Saved layout Phase 1: desiredAH=\(transitionAssessment.sets.desiredAlwaysHidden.sorted())"
                    )
                    MenuBarItemManager.diagLog.debug(
                        "Saved layout Phase 1: desiredVisible=\(transitionAssessment.sets.desiredVisible.sorted())"
                    )
                },
                recordTransitionControlMoveNeeded: { transitionAssessment in
                    MenuBarItemManager.diagLog.debug(
                        "Saved layout: \(transitionAssessment.crossSectionMoveCount) items would change hidden↔alwaysHidden, moving AH_ctrl instead"
                    )
                },
                recordControlMoveStart: { destination in
                    MenuBarItemManager.diagLog.debug("Saved layout: moving AH_ctrl → \(destination.logString)")
                },
                recordControlMoveFailure: { error in
                    MenuBarItemManager.diagLog.error("Saved layout: failed to move AH_ctrl: \(error)")
                },
                recordFallbackPlan: { fallbackPlan in
                    MenuBarItemManager.diagLog.debug(
                        "Saved layout: AH_ctrl placement left \(fallbackPlan.toAlwaysHidden.count) item(s) needing AH and \(fallbackPlan.toHidden.count) item(s) needing hidden, running per-item fallback"
                    )
                },
                recordFallbackMoveFailure: { fallbackMove, error in
                    MenuBarItemManager.diagLog.error(
                        "Saved layout: per-item move to \(fallbackMove.destination.diagnosticName) failed for \(fallbackMove.uniqueIdentifier): \(error)"
                    )
                },
                recordNoItemReorderingNeeded: { movedCount in
                    if movedCount > 0 {
                        MenuBarItemManager.diagLog.info(
                            "Saved layout: completed with \(movedCount) control item move(s), no item reordering needed"
                        )
                    } else {
                        MenuBarItemManager.diagLog.info("Saved layout: all items already in correct positions")
                    }
                },
                recordItemMovesNeeded: { plannedCount, movedCount in
                    MenuBarItemManager.diagLog.info(
                        "Saved layout: \(plannedCount) item move(s) needed (\(movedCount) control move(s) preceded)"
                    )
                },
                recordLCSMoveFailure: { uid, error in
                    MenuBarItemManager.diagLog.error(
                        "Saved layout: failed to move \(uid): \(error)"
                    )
                },
                recordCompletion: { movedCount in
                    MenuBarItemManager.diagLog.info("Saved layout: completed with \(movedCount) move(s)")
                }
            )
            if lcsOutcome.needsDeferredCacheRefresh {
                scheduleDeferredCacheRefresh()
                return
            }
            if lcsOutcome.stopReason == .cancelled {
                return
            }
            if lcsOutcome.plannedItemMoveCount == 0 {
                scheduleDeferredCacheRefresh()
                return
            }
        }

        // MARK: Phase 7: finalize (snapshot, cache, UI refresh)

        // Re-fetch items after moves so the follow-up cache cycle sees
        // the settled WindowServer state instead of the pre-apply snapshot.
        guard await observeActiveMenuBarItemsForRuntimeMutation(context: "final") != nil else {
            scheduleDeferredCacheRefresh()
            return
        }

        scheduleDeferredCacheRefresh()
    }

    /// Decides whether a windowID-set difference between two cache cycles is a
    /// genuine change that should trigger a saved-layout re-apply, or merely an
    /// artifact of the active menu bar display switching to another screen.
    ///
    /// With "Displays have separate Spaces" enabled the menu bar follows the
    /// active display, so on a switch the previous display's item windows leave
    /// the active-space window list and read as "missing" even though the same
    /// logical items are still present on the other screen. Treating that as an
    /// item quit fires a full bulk re-sort on every cross-screen focus change,
    /// which on a notched display drifts items into always-hidden. A display
    /// switch is not a layout edit, so it must not advance the gate; the
    /// divergence check still runs and catches genuine section drift.
    nonisolated static func windowIDsChanged(
        previous: Set<CGWindowID>,
        current: Set<CGWindowID>,
        previousDisplayID: CGDirectDisplayID?,
        currentDisplayID: CGDirectDisplayID?
    ) -> Bool {
        MenuBarSavedLayoutTrigger.windowIDsChanged(
            previous: previous,
            current: current,
            previousDisplayID: previousDisplayID,
            currentDisplayID: currentDisplayID
        )
    }

    /// Re-applies the user's saved menu-bar layout via the unified
    /// apply path. Builds the inputs that applySavedSectionLayout expects
    /// from savedSectionOrder and runs the shared discovery /
    /// unmanaged-placement / notch-overflow / execution machinery.
    ///
    /// Returns true if the bulk apply was dispatched (the body will
    /// drive its own follow-up cache cycle and the caller should not
    /// continue with the rest of its current cycle). Returns false
    /// when an entry guard rejects the call (no saved layout, cooldown
    /// active, no detected change to react
    /// to, no saved items currently present).
    func applySavedLayout(
        items: [MenuBarItem],
        previousWindowIDs: [CGWindowID],
        controlItems: MenuBarControlItems,
        previousDisplayID: CGDirectDisplayID? = nil,
        currentDisplayID: CGDirectDisplayID? = nil
    ) async -> Bool {
        // Each guard logs a distinct reason so a "Continuum stopped
        // restoring my layout" bug report can be diagnosed from the
        // first set of logs. Order is significant: the cheap state
        // checks run first; window-ID/tag inspection runs last so we
        // don't compute sets when an earlier guard would reject anyway.
        let activeSavedSectionOrder = MenuBarSavedOrderPolicy.prunedSavedSectionOrder(savedSectionOrder)
        if activeSavedSectionOrder != savedSectionOrder {
            savedSectionOrderLedger.replace(with: activeSavedSectionOrder)
            persistSavedSectionOrder()
            MenuBarItemManager.diagLog.debug("Pruned unstable identifiers from saved section order")
        }

        let decision = MenuBarSavedLayoutTrigger.evaluate(
            savedSectionOrder: activeSavedSectionOrder,
            items: items,
            controlItems: controlItems,
            previousWindowIDs: previousWindowIDs,
            previousDisplayID: previousDisplayID,
            currentDisplayID: currentDisplayID,
            relocationSuppressed: knownItemLedger.suppressesNextNewLeftmostItemRelocation,
            moveCooldownActive: lastMoveOperationOccurred(within: .seconds(5))
        )
        guard case let .apply(applyTrigger) = decision else {
            if case let .skip(reason) = decision {
                MenuBarItemManager.diagLog.debug("applySavedLayout: skipping, \(reason)")
            }
            return false
        }

        let itemSectionMap = MenuBarSavedLayoutTrigger.itemSectionMap(
            from: activeSavedSectionOrder
        )

        MenuBarItemManager.diagLog.info("applySavedLayout: dispatching bulk apply (\(applyTrigger))")
        diagnosticsRuntime.markState(.applying)

        // The shared body uses itemOrder as the per-section ordered
        // identifier list, which is structurally identical to
        // savedSectionOrder. Pass the saved order through unchanged.
        await applySavedSectionLayout(
            itemSectionMap: itemSectionMap,
            itemOrder: activeSavedSectionOrder
        )
        diagnosticsRuntime.markState(.verifying)
        return true
    }

    /// Restores items that are stuck in a "blocked" state (positioned at x=-1)
    /// back to the visible section. This is called when the app is terminating
    /// to prevent items from being permanently stuck in macOS's Control Center preferences.
    /// Only items at x=-1 are restored; normally hidden items are left as-is.
    ///
    /// - Returns: The number of items that failed to move.
    @MainActor
    func restoreBlockedItemsToVisible() async -> Int {
        MenuBarItemManager.diagLog.info("Checking for blocked items (x=-1) to restore before app termination")

        guard let appState else {
            MenuBarItemManager.diagLog.error("Cannot restore items: missing appState")
            return 0
        }

        guard let items = await observeActiveMenuBarItemsForRuntimeMutation(
            context: "restoreBlockedItems"
        ) else {
            return 0
        }

        let outcome = await MenuBarBlockedItemRecoveryExecutor.execute(
            items: items,
            controlItemWindowIDs: resolvedControlItemWindowIDs(),
            currentBoundsForItem: { Bridging.getWindowBounds(for: $0.windowID) },
            moveItem: { item, destination in
                try await move(
                    item: item,
                    to: destination,
                    skipInputPause: true,
                    watchdogTimeout: Self.layoutWatchdogTimeout
                )
            },
            recordNoCandidates: {
                MenuBarItemManager.diagLog.debug("No blocked items found - skipping restoration")
            },
            recordCandidatesFound: { count in
                MenuBarItemManager.diagLog.warning(
                    "Found \(count) blocked items at x=-1, attempting to restore"
                )
            },
            recordControlItemsMissing: { _ in
                MenuBarItemManager.diagLog.error("Cannot restore items: unable to find hidden control item")
            },
            beginMoveSession: {
                appState.hidEventManager.stopAll()
            },
            endMoveSession: {
                appState.hidEventManager.startAll()
            },
            recordMoveSuccess: { item in
                MenuBarItemManager.diagLog.info(
                    "Successfully restored blocked item \(item.logString) to visible section"
                )
            },
            recordMoveFailure: { item, error in
                MenuBarItemManager.diagLog.error("Failed to restore blocked item \(item.logString): \(error)")
            }
        )

        MenuBarItemManager.diagLog.info(
            "Restore completed: \(outcome.restoredCount)/\(outcome.attemptedCount) blocked items restored"
        )

        return outcome.failedCount
    }
}

// MARK: - Duration Helpers

private extension Duration {
    /// Returns the duration in milliseconds as a Double.
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
    }
}
