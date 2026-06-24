//
//  MenuBarManager.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

/// Manager for the state of the menu bar.
@MainActor
final class MenuBarManager: ObservableObject {
    /// Information for the menu bar's average color on the active screen.
    @Published private(set) var averageColorInfo: MenuBarAverageColorInfo?

    /// Per-screen average colors for multi-monitor adaptive backgrounds.
    @Published private(set) var averageColors: [CGDirectDisplayID: MenuBarAverageColorInfo] = [:]

    /// A Boolean value that indicates whether the menu bar is either always hidden
    /// by the system, or automatically hidden and shown by the system based on the
    /// location of the mouse.
    @Published private(set) var isMenuBarHiddenBySystem = false

    /// A Boolean value that indicates whether the menu bar is hidden by the system
    /// according to a value stored in UserDefaults.
    @Published private(set) var isMenuBarHiddenBySystemUserDefaults = false

    /// A Boolean value that indicates whether the "ShowOnHover" feature is allowed.
    @Published var showOnHoverAllowed = true

    /// Timestamp of the last time a section was shown.
    private(set) var lastShowTimestamp: ContinuousClock.Instant?

    /// Diagnostic logger for the menu bar manager.
    private let diagLog = DiagLog(category: "MenuBarManager")

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Per-item hotkeys, keyed by MenuBarItem.uniqueIdentifier. Each opens the
    /// item's menu when its key combination fires.
    @Published private(set) var itemHotkeys: [String: Hotkey] = [:]

    /// Reverse map from a hotkey instance to the item identifier it opens.
    /// Read by Hotkey.Listener when an openMenuBarItem hotkey fires.
    var hotkeyItemMap: [ObjectIdentifier: String] = [:]

    /// Per-item hotkey persistence observers, keyed by item identifier so a
    /// single binding can be torn down without disturbing the others.
    private var itemHotkeyCancellables = [String: AnyCancellable]()

    /// A Boolean value that indicates whether the application menus are hidden.
    private var isHidingApplicationMenus = false

    /// A Boolean value that indicates whether the application menus were hidden
    /// by a manual toggle (URL/hotkey), rather than automatically by section state.
    private var isManuallyHidingApplicationMenus = false

    /// The panel that contains the Overlay Tray interface.
    let overlayTrayPanel = OverlayTrayPanel()

    /// The managed sections in the menu bar.
    let sections = [
        MenuBarSection(name: .visible),
        MenuBarSection(name: .hidden),
        MenuBarSection(name: .alwaysHidden),
    ]

    /// A Boolean value that indicates whether at least one of the manager's
    /// sections is visible.
    var hasVisibleSection: Bool {
        sections.contains { !$0.isHidden }
    }

    /// Performs the initial setup of the menu bar manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        overlayTrayPanel.performSetup(with: appState)
        for section in sections {
            section.performSetup(with: appState)
        }
        rebuildItemHotkeys()
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.currentSystemPresentationOptions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] options in
                guard let self else {
                    return
                }
                let hidden = options.contains(.hideMenuBar) || options.contains(.autoHideMenuBar)
                isMenuBarHiddenBySystem = hidden
            }
            .store(in: &c)

        if
            let hiddenSection = section(withName: .alwaysHidden),
            let window = hiddenSection.controlItem.resolvedWindow()
        {
            window.publisher(for: \.frame)
                .map(\.origin.y)
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard
                        let self,
                        let isMenuBarHidden = Defaults.globalDomain["_HIHideMenuBar"] as? Bool
                    else {
                        return
                    }
                    isMenuBarHiddenBySystemUserDefaults = isMenuBarHidden
                }
                .store(in: &c)
        }

        // Handle the `focusedApp` and `smart` rehide strategies.
        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            // Ignore the initial value during app startup. Treating the
            // current frontmost app as a "focus change" immediately on launch
            // triggers an expensive menu-open scan before the item manager
            // has even finished its first cache pass.
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if
                    let self,
                    let appState,
                    let hiddenSection = section(withName: .hidden),
                    let screen = appState.hidEventManager.bestScreen(appState: appState),
                    !appState.hidEventManager.isMouseInsideMenuBar(appState: appState, screen: screen),
                    !appState.hidEventManager.isMouseInsideOverlayTray(appState: appState),
                    appState.settings.general.autoRehide
                {
                    // Handle both focusedApp and smart strategies for focus changes
                    switch appState.settings.general.rehideStrategy {
                    case .focusedApp, .smart:
                        Task {
                            // Add delay for smart strategy to allow app focus to settle
                            let delay: TimeInterval = appState.settings.general.rehideStrategy == .smart ? 0.25 : 0.1
                            try await Task.sleep(for: .seconds(delay))

                            // Ignore rehide requests for a short grace period after showing.
                            if let lastShow = self.lastShowTimestamp,
                               lastShow.duration(to: .now) < .milliseconds(500)
                            {
                                self.diagLog.debug("Skipping rehide due to grace period")
                                return
                            }

                            // Check if any menu bar item has a menu open (for smart strategy)
                            if appState.settings.general.rehideStrategy == .smart,
                               await appState.itemManager.isAnyMenuBarItemMenuOpen()
                            {
                                return
                            }

                            hiddenSection.hide()
                        }
                    default:
                        break
                    }
                }
            }
            .store(in: &c)

        if let appState {
            appState.settings.displaySettings.$configurations
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateControlItemStates()
                }
                .store(in: &c)

            // Refresh per-item hotkeys when the set of menu bar items changes,
            // so newly-arrived items become assignable. Debounced because the
            // item cache ticks frequently and rebuilding on every tick would
            // churn hotkey registrations.
            appState.itemManager.$itemCache
                .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.rebuildItemHotkeys()
                }
                .store(in: &c)
        }

        // Hide application menus when a section is shown (if applicable).
        Publishers.MergeMany(sections.map(\.controlItem.$state))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let appState else {
                    return
                }

                let activeMenuBarScreen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main

                // Don't continue if:
                //   * The "HideApplicationMenus" setting isn't enabled.
                //   * Using the Overlay Tray.
                //   * The menu bar is hidden by the system or not currently rendered.
                //   * The settings window is visible.
                guard
                    appState.settings.advanced.hideApplicationMenus,
                    !appState.settings.displaySettings.configurationForActiveDisplay().useOverlayTray,
                    !isMenuBarHiddenBySystem,
                    activeMenuBarScreen?.isSystemMenuBarVisible() != false,
                    !appState.navigationState.isSettingsPresented
                else {
                    return
                }

                // Check if hidden or alwaysHidden section is being shown
                let hiddenSection = self.section(withName: .hidden)
                let alwaysHiddenSection = self.section(withName: .alwaysHidden)

                // Use isHidden property - when section is shown, isHidden is false
                let isShowingHiddenSection = hiddenSection.map { !$0.isHidden } ?? false
                let isShowingAlwaysHiddenSection = alwaysHiddenSection.map { !$0.isHidden } ?? false

                if isShowingHiddenSection || isShowingAlwaysHiddenSection {
                    // Use the screen with the active menu bar
                    guard let screen = activeMenuBarScreen else {
                        return
                    }

                    Task {
                        // The window server needs time to update window positions after expansion.
                        try? await Task.sleep(for: .milliseconds(50))

                        // Get the app menu frame for this screen
                        guard let appMenuFrame = screen.getApplicationMenuFrame() else {
                            return
                        }

                        // Get ALL menu bar items
                        let allItems = await MenuBarItem.getMenuBarItems(option: .activeSpace)

                        // Filter to items on THIS screen by comparing Y coordinate with app menu's Y
                        let menuBarY = appMenuFrame.origin.y
                        let screenItems = allItems.filter { item in
                            abs(item.bounds.origin.y - menuBarY) < 50
                        }

                        // Get the control items for this screen
                        let hiddenControlItem = screenItems.first { $0.tag == .hiddenControlItem }
                        let alwaysHiddenControlItem = screenItems.first { $0.tag == .alwaysHiddenControlItem }

                        // Approximate hidden items width from control item positions.

                        // Get control item bounds and hidden items width
                        var controlBounds: CGRect = .zero
                        var hiddenItemsWidth: CGFloat = 0

                        if isShowingAlwaysHiddenSection, let ahControl = alwaysHiddenControlItem {
                            controlBounds = ahControl.bounds
                            if let appState = self.appState {
                                hiddenItemsWidth = appState.itemManager.itemCache[.alwaysHidden].reduce(0) { $0 + $1.bounds.width }
                            }
                        } else if isShowingHiddenSection, let hControl = hiddenControlItem {
                            controlBounds = hControl.bounds
                            if let appState = self.appState {
                                hiddenItemsWidth = appState.itemManager.itemCache[.hidden].reduce(0) { $0 + $1.bounds.width }
                            }
                        }

                        // The hidden section expands by replacing control item with hidden items
                        // New rightmost = where hidden items end = control.minX + hiddenItemsWidth
                        let newRightmostPos = controlBounds.minX + hiddenItemsWidth

                        // Use the actual app menu frame for needed space
                        let appMenuRightStart = appMenuFrame.maxX

                        // Available space: if app menu extends into notch, add notch width; otherwise use visible frame
                        let spaceAvailableFromAppMenuEnd: CGFloat = if let notch = screen.frameOfNotch {
                            if appMenuRightStart > notch.minX {
                                // App menu extends into notch, items get moved past notch
                                (notch.minX - appMenuRightStart) + (screen.visibleFrame.maxX - notch.maxX)
                            } else {
                                // App menu doesn't extend into notch
                                screen.visibleFrame.maxX - appMenuRightStart
                            }
                        } else {
                            screen.visibleFrame.maxX - appMenuRightStart
                        }

                        let spaceNeededFromAppMenuEnd = newRightmostPos - appMenuRightStart

                        // If items would extend past screen edge, hide the app menu
                        if spaceNeededFromAppMenuEnd > spaceAvailableFromAppMenuEnd {
                            self.hideApplicationMenus()
                        }
                    }
                } else if isHidingApplicationMenus, !isManuallyHidingApplicationMenus {
                    showApplicationMenus()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns a Boolean value that indicates whether the given display
    /// has a valid menu bar.
    func hasValidMenuBar(in windows: [WindowInfo], for display: CGDirectDisplayID) -> Bool {
        guard
            let window = WindowInfo.menuBarWindow(from: windows, for: display),
            let element = AXHelpers.element(at: window.bounds.origin)
        else {
            return false
        }
        return AXHelpers.role(for: element) == .menuBar
    }

    /// Shows the secondary context menu.
    func showSecondaryContextMenu(at point: CGPoint) {
        let menu = NSMenu(title: "\(Constants.displayName)")

        let settingsItem = NSMenuItem(
            title: String(localized: "\(Constants.displayName) Settings…"),
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
        menu.addItem(settingsItem)

        if appState?.settings.advanced.enableSecondaryContextMenuQuit == true {
            menu.addItem(.separator())

            let quitItem = NSMenuItem(
                title: String(localized: "Quit \(Constants.displayName)"),
                action: #selector(quitFromSecondaryContextMenu),
                keyEquivalent: "q"
            )
            quitItem.keyEquivalentModifierMask = .command
            quitItem.target = self
            quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
            menu.addItem(quitItem)

            let restartItem = NSMenuItem(
                title: String(localized: "Restart \(Constants.displayName)"),
                action: #selector(restartFromSecondaryContextMenu),
                keyEquivalent: "q"
            )
            restartItem.keyEquivalentModifierMask = [.command, .option]
            restartItem.isAlternate = true
            restartItem.target = self
            restartItem.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Restart")
            menu.addItem(restartItem)
        }

        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @objc private func quitFromSecondaryContextMenu() {
        // Defer NSApp.terminate until the main run loop is back in default mode.
        // The action fires inside popUp's eventTracking-mode nested run loop, and
        // popUp itself was invoked from a Task that is occupying the main actor.
        // Scheduling in .default only ensures the block runs after popUp tracking
        // unwinds and the enclosing Task completes, so terminate's wait loop can
        // drain the restore and timeout Tasks scheduled by applicationShouldTerminate.
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func restartFromSecondaryContextMenu() {
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                self?.appState?.restartSelf()
            }
        }
    }

    /// Hides the application menus.
    ///
    /// - Important: Uses `.regular` activation policy to hide menus, which briefly shows the app in the Dock.
    func hideApplicationMenus(manual: Bool = false) {
        guard let appState else {
            diagLog.error("Error hiding application menus: Missing app state")
            return
        }

        if isHidingApplicationMenus {
            return
        }

        diagLog.info("Hiding application menus")
        isHidingApplicationMenus = true
        if manual {
            isManuallyHidingApplicationMenus = true
        }

        // Ensure this happens on the main thread
        Task { @MainActor in
            guard isHidingApplicationMenus else { return }

            appState.activate(withPolicy: .regular)

            // Force activation again after a micro-delay.
            // The first activation after policy change can sometimes be ignored by the system.
            try? await Task.sleep(for: .milliseconds(25))
            guard isHidingApplicationMenus else { return }
            appState.activate()
        }
    }

    /// Shows the application menus.
    func showApplicationMenus() {
        guard let appState else {
            diagLog.error("Error showing application menus: Missing app state")
            return
        }
        diagLog.info("Showing application menus")
        appState.deactivate(withPolicy: .accessory)
        isHidingApplicationMenus = false
        isManuallyHidingApplicationMenus = false
    }

    /// Toggles the visibility of the application menus.
    func toggleApplicationMenus() {
        if isHidingApplicationMenus {
            showApplicationMenus()
        } else {
            hideApplicationMenus(manual: true)
        }
    }

    /// Updates the ``lastShowTimestamp`` property.
    func updateLastShowTimestamp() {
        lastShowTimestamp = .now
    }

    /// Updates the control item states for all sections.
    ///
    /// - Parameter screen: The screen to use for the update. If `nil`, the
    ///   best screen is determined automatically.
    func updateControlItemStates(for screen: NSScreen? = nil) {
        for section in sections {
            section.updateControlItemState(for: screen)
        }
    }

    /// Returns the menu bar section with the given name.
    func section(withName name: MenuBarSection.Name) -> MenuBarSection? {
        sections.first { $0.name == name }
    }

    /// Returns the control item for the menu bar section with the given name.
    func controlItem(withName name: MenuBarSection.Name) -> ControlItem? {
        section(withName: name)?.controlItem
    }

    // MARK: - Per-Item Hotkeys

    /// Creates and reconciles the per-item hotkeys, then observes their changes.
    ///
    /// Called during setup, whenever the item cache changes, and after a
    /// saved layout is restored. This is incremental:
    /// existing hotkey instances are preserved so a frequent cache tick does
    /// not tear down an in-use registration. A hotkey is created for every
    /// item currently in the menu bar plus every identifier that still has a
    /// saved binding (so a binding survives the owning app quitting), and is
    /// dropped only when its identifier is neither present nor configured.
    func rebuildItemHotkeys() {
        guard let appState else { return }

        let saved = Defaults.dictionary(forKey: .menuBarItemHotkeys) as? [String: Data] ?? [:]
        let dec = JSONDecoder()
        let enc = JSONEncoder()

        // Only real, identifiable items are assignable: skip Continuum's own control
        // items and items whose source app could not be resolved (their
        // identifier is an unstable UUID).
        let presentIdentifiers = Set(
            appState.itemManager.itemCache.managedItems
                .filter { !$0.isControlItem && $0.sourcePID != nil }
                .map(\.uniqueIdentifier)
        )
        let wantedIdentifiers = presentIdentifiers.union(saved.keys)

        var newHotkeys = itemHotkeys

        // Drop hotkeys for identifiers that are neither present nor configured.
        for (identifier, hotkey) in itemHotkeys where !wantedIdentifiers.contains(identifier) {
            hotkey.disable()
            hotkeyItemMap[ObjectIdentifier(hotkey)] = nil
            itemHotkeyCancellables[identifier] = nil
            newHotkeys[identifier] = nil
        }

        for identifier in wantedIdentifiers {
            let savedCombo: KeyCombination? = saved[identifier].flatMap { data in
                try? dec.decode(KeyCombination?.self, from: data)
            }

            if let existing = newHotkeys[identifier] {
                // Reconcile the live binding to the saved value (e.g. after a
                // saved-layout apply). Only assign when it actually differs so we
                // avoid a redundant write back through the persistence sink.
                if existing.keyCombination != savedCombo {
                    existing.keyCombination = savedCombo
                }
                continue
            }

            let hotkey = Hotkey(action: .openMenuBarItem)
            hotkey.performSetup(with: appState)
            hotkey.keyCombination = savedCombo
            hotkeyItemMap[ObjectIdentifier(hotkey)] = identifier

            // Observe future changes from HotkeyRecorder and persist them.
            itemHotkeyCancellables[identifier] = hotkey.$keyCombination
                .dropFirst() // Skip the initial value we just set.
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak hotkey] newCombo in
                    guard let self, let hotkey else { return }
                    var dict = Defaults.dictionary(forKey: .menuBarItemHotkeys) as? [String: Data] ?? [:]
                    if let combo = newCombo, let data = try? enc.encode(combo) {
                        dict[identifier] = data
                    } else {
                        dict.removeValue(forKey: identifier)
                    }
                    Defaults.set(dict, forKey: .menuBarItemHotkeys)
                    self.hotkeyItemMap[ObjectIdentifier(hotkey)] = newCombo != nil ? identifier : nil
                }

            newHotkeys[identifier] = hotkey
        }

        itemHotkeys = newHotkeys
    }

    /// Opens the menu of the menu bar item with the given identifier.
    ///
    /// Resolves the live item from the current cache and routes it through the
    /// shared activation path. No-ops if the item is not currently present
    /// (e.g. its owning app has been quit).
    func openItem(withIdentifier identifier: String) {
        guard let appState else { return }
        let displayID = NSScreen.screenWithActiveMenuBar?.displayID
        Task {
            await appState.itemManager.activateItem(
                withIdentifier: identifier,
                on: displayID
            )
        }
    }
}

// MARK: - MenuBarAverageColorInfo

/// Information for the average color of the menu bar.
struct MenuBarAverageColorInfo: Hashable {
    /// Sources used to compute the average color of the menu bar.
    enum Source: Hashable {
        case menuBarWindow
        case desktopWallpaper
    }

    /// The average color of the menu bar
    var color: CGColor

    /// The source used to compute the color.
    var source: Source

    /// The brightness of the menu bar's color.
    var brightness: CGFloat {
        color.brightness ?? 0
    }

    /// A Boolean value that indicates whether the menu bar has a
    /// bright color.
    ///
    /// This value is `true` if ``brightness`` is above ``Constants.menuBarBrightnessThreshold``.
    /// At the time of writing, if this value is `true`, the menu bar
    /// draws its items with a darker appearance.
    var isBright: Bool {
        brightness > Constants.menuBarBrightnessThreshold
    }

    /// Returns whether the menu bar has a bright color for the given screen.
    /// Uses a lower threshold for notched displays to bias toward black text.
    /// - Parameter screen: The screen to check for notch presence
    /// - Returns: `true` if the background is bright enough to require dark text
    func isBright(for screen: NSScreen?) -> Bool {
        let activeOrPassed = screen ?? NSScreen.screenWithActiveMenuBar
        let hasNotch = activeOrPassed?.hasNotch == true
        let threshold = hasNotch
            ? Constants.notchedDisplayBrightnessThreshold
            : Constants.menuBarBrightnessThreshold
        return brightness > threshold
    }
}
