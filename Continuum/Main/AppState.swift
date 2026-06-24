//
//  AppState.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

/// The model for app-wide state.
@MainActor
final class AppState: ObservableObject {
    /// A Boolean value that indicates whether the user is dragging a menu bar item.
    @Published private(set) var isDraggingMenuBarItem = false

    /// Tracks presentation of the update consent sheet.
    @Published var isUpdateConsentPresented = false

    /// Tracks presentation of the onboarding sheet.
    @Published var isOnboardingPresented = false

    /// Model for the app's settings.
    let settings = AppSettings()

    /// Model for the app's permissions.
    let permissions = AppPermissions()

    /// Model for app-wide navigation.
    let navigationState = AppNavigationState()

    /// Manager for the state of the menu bar.
    let menuBarManager = MenuBarManager()

    /// Manager for menu bar items.
    let itemManager = MenuBarItemManager()

    /// Global cache for menu bar item images.
    let imageCache = MenuBarItemImageCache()

    /// Manager for input events received by the app.
    let hidEventManager = HIDEventManager()

    /// Manager for app updates.
    let updatesManager = UpdatesManager()

    /// Manager for user notifications.
    let userNotificationManager = UserNotificationManager()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Track open windows to prevent duplicates
    private var openWindows = Set<ContinuumWindowIdentifier>()

    /// Prevent repeated restart attempts.
    private var isRestarting = false

    /// Diagnostic logger for the app state.
    let diagLog = DiagLog(category: "AppState")

    private lazy var setupTask = Task { @MainActor in
        #if DEBUG
            // Debug builds always have diagnostic logging on so logs are
            // captured during development without depending on the toggle.
            DiagnosticLogger.shared.isEnabled = true
        #else
            if Defaults.bool(forKey: .enableDiagnosticLogging) {
                DiagnosticLogger.shared.isEnabled = true
            }
        #endif

        diagLog.debug("setupTask: starting AppState setup sequence")
        permissions.stopAllChecks()
        diagLog.debug("setupTask: permissions state = \(String(describing: self.permissions.permissionsState)), accessibility = \(self.permissions.accessibility.hasPermission)")

        settings.performSetup(with: self)
        menuBarManager.performSetup(with: self)
        diagLog.debug("setupTask: settings and menuBarManager setup complete")

        diagLog.debug("setupTask: starting source PID cache")
        SourcePIDCache.shared.start()
        diagLog.debug("setupTask: source PID cache started")

        hidEventManager.performSetup(with: self)
        diagLog.debug("setupTask: starting itemManager setup")
        await itemManager.performSetup(with: self)
        diagLog.debug("setupTask: itemManager setup scheduled, invalidating menuBarHeightCache")
        NSScreen.invalidateMenuBarHeightCache()
        updatesManager.performSetup(with: self)
        userNotificationManager.performSetup(with: self)

        configureCancellables()
        diagLog.debug("setupTask: AppState setup sequence complete")
    }

    /// Allows explicit starting of the updater from UI flows.
    func startUpdaterIfNeeded() {
        updatesManager.startUpdaterIfNeeded()
    }

    /// Presents the onboarding sheet if the user hasn't seen it yet.
    func presentOnboardingIfNeeded() {
        if !Defaults.bool(forKey: .hasSeenOnboarding) {
            isOnboardingPresented = true
        }
    }

    /// Completes first-launch setup based on the permissions currently granted,
    /// then brings the app to regular activation and opens Settings. Shared by
    /// the permissions window's Continue button and onboarding's final slide.
    func completeFirstLaunchSetup() {
        dismissWindow(.permissions)
        Defaults.set(true, forKey: .hasSeenOnboarding)

        let hasPermissions = permissions.permissionsState != .missing
        performSetup(hasPermissions: hasPermissions)
        Defaults.set(true, forKey: .hasCompletedFirstLaunch)

        guard hasPermissions else { return }

        Task {
            activate(withPolicy: .regular)
            openWindow(.settings)
        }
    }

    func dismissWindow(_ id: ContinuumWindowIdentifier) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.openWindows.remove(id)
            self.diagLog.debug("Dismissing window with id: \(id)")
            EnvironmentValues().dismissWindow(id: id)
        }
    }

    /// Performs app state setup.
    ///
    /// - Parameter hasPermissions: If `true`, continues with setup normally.
    ///   If `false`, prompts the user to grant permissions.
    func performSetup(hasPermissions: Bool) {
        if hasPermissions {
            Task {
                diagLog.debug("Setting up app state")
                await setupTask.value

                // Warm up the activation policy system.
                NSApp.setActivationPolicy(.regular)
                try? await Task.sleep(for: .milliseconds(50))
                NSApp.setActivationPolicy(.accessory)

                diagLog.debug("Finished setting up app state")
            }
        } else {
            Task {
                // Delay to prevent conflicts with the app delegate.
                try? await Task.sleep(for: .milliseconds(100))
                activate(withPolicy: .regular)
                dismissWindow(.settings) // Shouldn't be open anyway.
                openWindow(.permissions)
            }
        }
    }

    /// Configures the internal observers for the app state.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .receive(on: DispatchQueue.main)
            .map { $0 == .current }
            .removeDuplicates()
            .sink { [weak self] isFrontmost in
                self?.navigationState.isAppFrontmost = isFrontmost
            }
            .store(in: &c)

        publisherForWindow(.settings)
            .removeNil()
            .map { $0.publisher(for: \.isVisible) }
            .switchToLatest()
            .replaceEmpty(with: false)
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .removeDuplicates()
            .sink { [weak self] isPresented in
                guard let self else { return }
                self.navigationState.isSettingsPresented = isPresented

                // Update openWindows tracking based on actual window visibility
                if isPresented {
                    self.openWindows.insert(.settings)
                    // Start Sparkle consent flow the first time settings is shown.
                    if !Defaults.bool(forKey: .hasSeenUpdateConsent) {
                        self.isUpdateConsentPresented = true
                    } else {
                        self.updatesManager.startUpdaterIfNeeded()
                        self.presentOnboardingIfNeeded()
                    }
                } else {
                    self.openWindows.remove(.settings)
                    self.deactivate(withPolicy: .accessory)
                }
            }
            .store(in: &c)

        hidEventManager.$isDraggingMenuBarItem
            .removeDuplicates()
            .sink { [weak self] isDragging in
                self?.isDraggingMenuBarItem = isDragging
            }
            .store(in: &c)

        menuBarManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        permissions.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        settings.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        updatesManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        cancellables = c
    }

    /// Relaunches the current app instance silently.
    func restartSelf() {
        guard !isRestarting else { return }
        isRestarting = true

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        config.createsNewApplicationInstance = true
        config.promptsUserIfNeeded = false

        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
                try? await Task.sleep(for: .milliseconds(500))
                exit(0)
            } catch {
                diagLog.error("Failed to relaunch app: \(error.localizedDescription)")
                isRestarting = false
            }
        }
    }

    /// Returns a Boolean value indicating whether the app has been
    /// granted the permission associated with the given key.
    func hasPermission(_ key: AppPermissions.PermissionKey) -> Bool {
        switch key {
        case .accessibility:
            permissions.accessibility.hasPermission
        }
    }

    /// Returns a publisher for the window with the given identifier.
    func publisherForWindow(_ id: ContinuumWindowIdentifier) -> some Publisher<NSWindow?, Never> {
        NSApp.publisher(for: \.windows)
            .map { windows in
                windows.first { $0.identifier?.rawValue == id.rawValue }
            }
    }

    func openWindow(_ id: ContinuumWindowIdentifier) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if self.openWindows.contains(id) {
                self.diagLog.debug("Window \(id) already open, activating existing window")
                self.activate(withPolicy: .regular)
                return
            }

            self.openWindows.insert(id)
            self.diagLog.debug("Opening window with id: \(id)")
            EnvironmentValues().openWindow(id: id)

            try? await Task.sleep(for: .milliseconds(100))
            self.activate(withPolicy: .regular)
        }
    }

    func activate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        if let policy {
            NSApp.setActivationPolicy(policy)
        }

        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard let frontmost = NSWorkspace.shared.frontmostApplication else {
                NSRunningApplication.current.activate()
                return
            }
            NSRunningApplication.current.activate(from: frontmost)
        }
    }

    /// Deactivates the app and sets its activation policy.
    func deactivate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        if let policy {
            NSApp.setActivationPolicy(policy)
        }
        NSApp.deactivate()
    }
}
