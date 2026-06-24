//
//  OverlayTray.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

// MARK: - OverlayTrayPanel

final class OverlayTrayPanel: NSPanel {
    private let diagLog = DiagLog(category: "OverlayTrayPanel")
    /// The shared app state.
    private weak var appState: AppState?

    /// Manager for the Overlay Tray's color.
    private let colorManager = OverlayTrayColorManager()

    /// The currently displayed section.
    private(set) var currentSection: MenuBarSection.Name?

    /// A Boolean value that indicates whether to show the panel at
    /// the mouse pointer's location, regardless of the user's
    /// settings.
    private var hotkeyLocationOverride = false

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Background cache task started when the panel is shown.
    private var cacheTask: Task<Void, Never>?

    /// Creates a new Overlay Tray panel with Liquid Glass support.
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        self.title = String(localized: "\(Constants.displayName) Bar")
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.allowsToolTipsWhenApplicationIsInactive = true
        self.isFloatingPanel = true
        self.animationBehavior = .none
        // Liquid Glass: transparent window with shadow
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.level = .mainMenu + 1
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace, .stationary]
        self.hidesOnDeactivate = false
        self.canHide = false
    }

    /// Sets up the panel.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        colorManager.performSetup(with: self)
    }

    /// Configures the internal observers.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Update the panel's origin whenever its size changes.
        publisher(for: \.frame).map(\.size)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, let screen else {
                    return
                }
                updateOrigin(for: screen)
            }
            .store(in: &c)

        cancellables = c
    }

    /// Updates the panel's frame origin for display on the given screen.
    private func updateOrigin(for screen: NSScreen) {
        guard let appState else {
            return
        }

        func getOrigin(for overlayTrayLocation: OverlayTrayLocation) -> CGPoint {
            let menuBarHeight = screen.getMenuBarHeightEstimate()
            let defaultOriginY = ((screen.frame.maxY - 1) - menuBarHeight) - frame.height

            var originForRightOfScreen: CGPoint {
                CGPoint(x: screen.frame.maxX - frame.width, y: defaultOriginY)
            }

            if hotkeyLocationOverride, let location = MouseHelpers.locationAppKit {
                let lowerBoundX = screen.frame.minX
                let upperBoundX = screen.frame.maxX - frame.width
                let lowerBoundY = screen.frame.minY
                let upperBoundY = screen.frame.maxY - frame.height

                let x = (location.x - frame.width / 2).clamped(to: lowerBoundX ... (upperBoundX > lowerBoundX ? upperBoundX : lowerBoundX))
                let y = (location.y - frame.height / 2).clamped(to: lowerBoundY ... (upperBoundY > lowerBoundY ? upperBoundY : lowerBoundY))

                return CGPoint(x: x, y: y)
            }

            switch overlayTrayLocation {
            case .dynamic:
                if appState.hidEventManager.isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) {
                    return getOrigin(for: .mousePointer)
                }
                return getOrigin(for: .controlIcon)
            case .mousePointer:
                guard let location = MouseHelpers.locationAppKit else {
                    return getOrigin(for: .controlIcon)
                }

                let lowerBoundX = screen.frame.minX
                let upperBoundX = screen.frame.maxX - frame.width

                guard lowerBoundX <= upperBoundX else {
                    return originForRightOfScreen
                }

                let x = (location.x - frame.width / 2).clamped(to: lowerBoundX ... upperBoundX)

                return CGPoint(x: x, y: defaultOriginY)
            case .controlIcon:
                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard
                    lowerBound <= upperBound,
                    let controlItem = appState.itemManager.itemCache.managedItems.first(matching: .visibleControlItem),
                    // Bridging API is more reliable than controlItem.frame in some
                    // cases (like if the item is offscreen).
                    let itemBounds = Bridging.getWindowBounds(for: controlItem.windowID)
                else {
                    return originForRightOfScreen
                }

                return CGPoint(x: (itemBounds.midX - frame.width / 2).clamped(to: lowerBound ... upperBound), y: defaultOriginY)
            case .leftAligned:
                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard lowerBound <= upperBound else {
                    return originForRightOfScreen
                }

                let x = (screen.frame.minX + 24).clamped(to: lowerBound ... upperBound)
                return CGPoint(x: x, y: defaultOriginY)
            case .rightAligned:
                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard lowerBound <= upperBound else {
                    return originForRightOfScreen
                }

                let x = (screen.frame.maxX - frame.width - 24).clamped(to: lowerBound ... upperBound)
                return CGPoint(x: x, y: defaultOriginY)
            }
        }

        let location = appState.settings.displaySettings.overlayTrayLocation(for: screen.displayID)
        setFrameOrigin(getOrigin(for: location))
    }

    /// Shows the panel on the given screen, displaying the given
    /// menu bar section.
    func show(
        section: MenuBarSection.Name,
        on screen: NSScreen,
        triggeredByHotkey: Bool = false
    ) {
        guard let appState else {
            return
        }

        let menuBarHeight = screen.getMenuBarHeightEstimate()
        diagLog.notice("""
        show: screen=\(screen.displayID) \
        backingScaleFactor=\(Double(screen.backingScaleFactor)) \
        hasNotch=\(screen.hasNotch) \
        menuBarHeight=\(Double(menuBarHeight)) \
        frame=\(screen.frame.debugDescription) \
        visibleFrame=\(screen.visibleFrame.debugDescription)
        """)

        hotkeyLocationOverride = triggeredByHotkey && appState.settings.general.overlayTrayLocationOnHotkey

        // IMPORTANT: We must set the navigation state and current section
        // before updating the caches.
        appState.navigationState.isOverlayTrayPresented = true
        currentSection = section

        // Show the panel immediately with whatever cached data we have.
        // The SwiftUI view observes itemManager and imageCache, so it
        // will re-render automatically as the background updates land.
        contentView = OverlayTrayHostingView(
            appState: appState,
            colorManager: colorManager,
            screen: screen,
            section: section
        )

        updateOrigin(for: screen)

        // Color manager must be updated after updating the panel's origin,
        // but before it is shown.
        //
        // Color manager handles frame changes automatically, but does so on
        // the main queue, so we need to update manually once before showing
        // the panel to prevent the color from flashing.
        colorManager.updateAllProperties(with: frame, screen: screen)

        orderFrontRegardless()

        // Rehide temporarily shown items and refresh caches in the
        // background. Ordering is preserved: rehide moves items back
        // to their correct sections before the cache is rebuilt.
        // The task is cancelled in close() to avoid holding appState.
        cacheTask?.cancel()
        cacheTask = Task { [weak appState] in
            guard let appState else { return }
            await appState.itemManager.rehideTemporarilyShownItems(force: true)
            guard !Task.isCancelled else { return }
            // Settle delay: when the OverlayTray just opened on a screen that
            // was previously inactive, the menu bar has moved screens and
            // NSStatusItem windows (control item chevrons) are still
            // positioning. Without this delay, cacheItemsIfNeeded can
            // recache with stale/zero control item bounds, causing
            // findSection() to misclassify all items as .visible and
            // leave the hidden section cache empty ("No items…").
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await appState.itemManager.cacheItemsIfNeeded()
            guard !Task.isCancelled else { return }
            await appState.imageCache.updateCache()
        }
    }

    /// Hides the panel.
    func hide() {
        if
            let name = currentSection,
            let section = appState?.menuBarManager.section(withName: name)
        {
            section.hide()
        }
        close()
    }

    override func close() {
        CustomTooltipPanel.shared.dismiss()
        cacheTask?.cancel()
        cacheTask = nil
        contentView = nil
        orderOut(nil)
        super.close()
        currentSection = nil
        appState?.navigationState.isOverlayTrayPresented = false
    }

    /// Resizes the panel to match the hosting view's intrinsic content size.
    func resizeToContent() {
        guard let contentView, let screen else { return }
        let ideal = contentView.intrinsicContentSize
        guard ideal != .zero, ideal != frame.size else { return }
        setFrame(NSRect(origin: frame.origin, size: ideal), display: true, animate: false)
        updateOrigin(for: screen)
    }
}

// MARK: - OverlayTrayHostingView

private final class OverlayTrayHostingView: NSHostingView<OverlayTrayContentView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    override func layout() {
        super.layout()
        (window as? OverlayTrayPanel)?.resizeToContent()
    }

    init(
        appState: AppState,
        colorManager: OverlayTrayColorManager,
        screen: NSScreen,
        section: MenuBarSection.Name
    ) {
        let rootView = OverlayTrayContentView(
            appState: appState,
            colorManager: colorManager,
            itemManager: appState.itemManager,
            imageCache: appState.imageCache,
            menuBarManager: appState.menuBarManager,
            screen: screen,
            section: section
        )
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView _: OverlayTrayContentView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - OverlayTrayContentView

private struct OverlayTrayContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var colorManager: OverlayTrayColorManager
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var imageCache: MenuBarItemImageCache
    @ObservedObject var menuBarManager: MenuBarManager
    @State private var frame = CGRect.zero
    @State private var scrollIndicatorsFlashTrigger = 0
    @State private var cacheGracePeriodActive = true
    @State private var loadingTimedOut = false

    let screen: NSScreen
    let section: MenuBarSection.Name

    private var items: [MenuBarItem] {
        itemManager.itemCache.managedItems(for: section)
    }

    private var displaySettings: DisplaySettingsManager {
        appState.settings.displaySettings
    }

    private var layout: OverlayTrayLayout {
        displaySettings.configuration(for: screen.displayID).overlayTrayLayout
    }

    private var gridColumns: Int {
        displaySettings.configuration(for: screen.displayID).gridColumns
    }

    private var itemSpacing: CGFloat {
        0
    }

    private var horizontalPadding: CGFloat {
        3
    }

    private var verticalPadding: CGFloat {
        0
    }

    private var contentHeight: CGFloat {
        screen.getMenuBarHeightEstimate()
    }

    private var itemMaxHeight: CGFloat? {
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        return menuBarHeight > 0 ? menuBarHeight : nil
    }

    /// The maximum rendered width of any item in the current section.
    private var maxItemWidth: CGFloat {
        guard let maxHeight = itemMaxHeight, maxHeight > 0 else { return 0 }
        let widths = items.compactMap { item -> CGFloat? in
            guard let cachedImage = imageCache.images[item.tag] else { return nil }
            let image = cachedImage.nsImage
            guard image.size.height > 0 else { return image.size.width }
            let scale = maxHeight / image.size.height
            return image.size.width * scale
        }
        return widths.max() ?? maxHeight
    }

    /// Per-column maximum widths for the grid layout.
    private var columnWidths: [CGFloat] {
        guard let maxHeight = itemMaxHeight, maxHeight > 0 else { return [] }
        let allItems = items
        let rows = stride(from: 0, to: allItems.count, by: gridColumns).map { start in
            Array(allItems[start ..< Swift.min(start + gridColumns, allItems.count)])
        }
        return (0 ..< gridColumns).map { col in
            rows.compactMap { row in
                guard col < row.count else { return nil }
                guard let cachedImage = imageCache.images[row[col].tag] else { return nil }
                let image = cachedImage.nsImage
                guard image.size.height > 0 else { return image.size.width }
                let scale = maxHeight / image.size.height
                return image.size.width * scale
            }.max() ?? 0
        }
    }

    /// Maximum content height for vertical and grid layouts so the panel
    /// does not extend below the visible screen area.
    private var maxContentHeight: CGFloat {
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        let available = (screen.frame.maxY - menuBarHeight) - screen.visibleFrame.minY
        let totalPadding: CGFloat = 10 + verticalPadding * 2
        return max(available - totalPadding, contentHeight)
    }

    /// Total intrinsic height of all items/rows for the current layout.
    private var totalContentHeight: CGFloat {
        switch layout {
        case .horizontal:
            return contentHeight
        case .vertical:
            return CGFloat(items.count) * contentHeight
        case .grid:
            let rowCount = Int(ceil(Double(items.count) / Double(gridColumns)))
            return CGFloat(rowCount) * contentHeight
        }
    }

    private var clipShape: some InsettableShape {
        RoundedRectangle(cornerRadius: contentHeight / 2, style: .circular)
    }

    var body: some View {
        ZStack {
            Group {
                if layout == .horizontal {
                    content.frame(height: contentHeight)
                } else {
                    content.frame(height: min(totalContentHeight, maxContentHeight))
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .menuBarItemContainer(appState: appState, colorInfo: colorManager.colorInfo)
            .foregroundStyle(colorManager.colorInfo?.isBright(for: screen) == true ? .black : .white)
            .clipShape(clipShape)
        }
        .padding(5)
        .frame(maxWidth: screen.frame.width)
        .fixedSize(horizontal: true, vertical: layout == .horizontal)
        .onAppear {
            Self.diagLog.notice("""
            OverlayTrayContentView appeared: \
            displayID=\(screen.displayID) \
            backingScaleFactor=\(Double(screen.backingScaleFactor)) \
            hasNotch=\(screen.hasNotch) \
            contentHeight=\(Double(contentHeight)) \
            itemMaxHeight=\(Double(itemMaxHeight ?? 0)) \
            menuBarHeight=\(Double(screen.getMenuBarHeightEstimate())) \
            layout=\(String(describing: layout)) \
            items=\(items.count) \
            section=\(section.logString)
            """)
        }
        .onFrameChange(update: $frame)
        .task(id: section) {
            cacheGracePeriodActive = true
            loadingTimedOut = false
            try? await Task.sleep(for: .milliseconds(600))
            cacheGracePeriodActive = false
            try? await Task.sleep(for: .seconds(2))
            loadingTimedOut = true
        }
    }

    private static let diagLog = DiagLog(category: "OverlayTray.Content")

    private func openPermissionsWindow() {
        menuBarManager.section(withName: section)?.hide()
        appState.activate(withPolicy: .regular)
        appState.openWindow(.permissions)
    }

    @ViewBuilder
    private var content: some View {
        if section == .alwaysHidden || section == .hidden, items.isEmpty {
            HStack {
                if cacheGracePeriodActive {
                    Text("Loading menu bar items…")
                } else if !loadingTimedOut {
                    Text("No items in this section")
                } else {
                    Text("No items in this section")
                }
            }
            .padding(.horizontal, 10)
            .onChange(of: cacheGracePeriodActive) {
                Self.diagLog.debug("OverlayTray content: grace period changed to \(self.cacheGracePeriodActive) for section \(self.section.logString) — items still empty: \(self.items.isEmpty)")
            }
            .onChange(of: loadingTimedOut) {
                Self.diagLog.debug("OverlayTray content: loading timeout changed to \(self.loadingTimedOut) for section \(self.section.logString) — items still empty: \(self.items.isEmpty)")
            }
            .onAppear {
                Self.diagLog.debug("OverlayTray content: showing '\(self.cacheGracePeriodActive ? "Loading…" : "No items")' for section \(self.section.logString) (grace period active: \(self.cacheGracePeriodActive))")
            }
        } else if itemManager.itemCache.managedItems.isEmpty {
            HStack {
                if loadingTimedOut {
                    Text("Unable to load menu bar items")
                    Button {
                        openPermissionsWindow()
                    } label: {
                        Text("Check permissions")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.link)
                } else {
                    Text("Loading menu bar items…")
                }
            }
            .padding(.horizontal, 10)
            .onChange(of: loadingTimedOut) {
                Self.diagLog.warning("OverlayTray content: loading timeout changed to \(self.loadingTimedOut) — itemCache.managedItems is still EMPTY")
            }
            .onAppear {
                Self.diagLog.warning("OverlayTray content: showing 'Loading menu bar items…' — itemCache.managedItems is EMPTY. This means the item cache has never been populated.")
            }
        } else if imageCache.cacheFailed(for: section) {
            HStack {
                if cacheGracePeriodActive {
                    Text("Loading menu bar items…")
                } else if loadingTimedOut {
                    // Final state: no further automatic retry.
                    Text("Unable to display menu bar items")
                    Button {
                        openPermissionsWindow()
                    } label: {
                        Text("Check permissions")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.link)
                } else {
                    Text("Loading menu bar items…")
                }
            }
            .padding(.horizontal, 10)
            .onChange(of: loadingTimedOut) {
                Self.diagLog.warning("OverlayTray content: cacheFailed timeout changed to \(self.loadingTimedOut) for section \(self.section.logString)")
            }
            .onAppear {
                Self.diagLog.warning("OverlayTray content: showing '\(self.cacheGracePeriodActive ? "Loading…" : "Unable to display")' for section \(self.section.logString) — imageCache.cacheFailed=true (grace period active: \(self.cacheGracePeriodActive), loadingTimedOut: \(self.loadingTimedOut), cached images count: \(self.imageCache.images.count), items in section: \(self.itemManager.itemCache[self.section].count))")
            }
        } else {
            let isLightBackground = colorManager.colorInfo?.isBright(for: screen) == true
            switch layout {
            case .horizontal:
                ScrollView(.horizontal) {
                    HStack(spacing: itemSpacing) {
                        ForEach(items, id: \.windowID) { item in
                            OverlayTrayItemView(
                                imageCache: imageCache,
                                itemManager: itemManager,
                                menuBarManager: menuBarManager,
                                item: item,
                                section: section,
                                displayID: screen.displayID,
                                maxHeight: itemMaxHeight,
                                hasRoundedShape: true,
                                tooltipDelay: appState.settings.advanced.tooltipDelay,
                                isLightBackground: isLightBackground
                            )
                        }
                    }
                    .frame(height: contentHeight)
                }
                .environment(\.isScrollEnabled, frame.width == screen.frame.width)
                .defaultScrollAnchor(.trailing)
                .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
                .task {
                    scrollIndicatorsFlashTrigger += 1
                }

            case .vertical:
                ScrollView(.vertical) {
                    VStack(spacing: itemSpacing) {
                        ForEach(items, id: \.windowID) { item in
                            OverlayTrayItemView(
                                imageCache: imageCache,
                                itemManager: itemManager,
                                menuBarManager: menuBarManager,
                                item: item,
                                section: section,
                                displayID: screen.displayID,
                                maxHeight: itemMaxHeight,
                                hasRoundedShape: true,
                                tooltipDelay: appState.settings.advanced.tooltipDelay,
                                isLightBackground: isLightBackground
                            )
                        }
                    }
                }
                .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
                .task {
                    scrollIndicatorsFlashTrigger += 1
                }

            case .grid:
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        let rows = stride(from: 0, to: items.count, by: gridColumns).map { start in
                            Array(items[start ..< Swift.min(start + gridColumns, items.count)])
                        }
                        ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowItems in
                            HStack(spacing: itemSpacing) {
                                ForEach(Array(rowItems.enumerated()), id: \.element.windowID) { colIndex, item in
                                    let itemView = OverlayTrayItemView(
                                        imageCache: imageCache,
                                        itemManager: itemManager,
                                        menuBarManager: menuBarManager,
                                        item: item,
                                        section: section,
                                        displayID: screen.displayID,
                                        maxHeight: itemMaxHeight,
                                        hasRoundedShape: true,
                                        tooltipDelay: appState.settings.advanced.tooltipDelay,
                                        isLightBackground: isLightBackground
                                    )
                                    if rows.count > 1 {
                                        itemView
                                            .frame(width: columnWidths[colIndex], alignment: .center)
                                    } else {
                                        itemView
                                    }
                                }
                                // Only pad the last row when there are multiple rows,
                                // so partial rows align with the columns above.
                                if rows.count > 1, rowIndex == rows.count - 1, rowItems.count < gridColumns {
                                    ForEach(rowItems.count ..< gridColumns, id: \.self) { colIndex in
                                        Color.clear
                                            .frame(width: columnWidths[colIndex], height: contentHeight)
                                    }
                                }
                            }
                            .frame(height: contentHeight)
                        }
                    }
                }
                .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
                .task {
                    scrollIndicatorsFlashTrigger += 1
                }
            }
        }
    }
}

// MARK: - OverlayTrayItemView

private struct OverlayTrayItemView: View {
    private static let diagLog = DiagLog(category: "OverlayTray.ItemView")

    @ObservedObject var imageCache: MenuBarItemImageCache
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var menuBarManager: MenuBarManager

    @State private var isHovered = false

    let item: MenuBarItem
    let section: MenuBarSection.Name
    let displayID: CGDirectDisplayID
    let maxHeight: CGFloat?
    let hasRoundedShape: Bool
    let tooltipDelay: TimeInterval
    let isLightBackground: Bool

    private var pillCornerRadius: CGFloat {
        guard let h = maxHeight, h > 0 else { return 4 }
        return hasRoundedShape ? h / 2 : h / 4
    }

    private var leftClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            let clickStartTime = Date.now
            OverlayTrayItemView.diagLog.debug("leftClick: user clicked \(item.logString)")
            let panel = menuBarManager.overlayTrayPanel
            parkCursorAwayFromHotCorners()
            menuBarManager.section(withName: section)?.hide()
            Task {
                // Wait until the OverlayTray panel is fully closed before checking
                // item visibility. Uses KVO on isVisible so we resume as soon
                // as the panel hides rather than busy-polling.
                await panel.waitUntilClosed(timeout: .milliseconds(200))
                await activateTrayItem(
                    with: .left,
                    actionName: "leftClick",
                    clickStartTime: clickStartTime,
                    itemManager: itemManager
                )
            }
        }
    }

    private var rightClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            let clickStartTime = Date.now
            OverlayTrayItemView.diagLog.debug("rightClick: user clicked \(item.logString)")
            let panel = menuBarManager.overlayTrayPanel
            parkCursorAwayFromHotCorners()
            menuBarManager.section(withName: section)?.hide()
            Task {
                await panel.waitUntilClosed(timeout: .milliseconds(200))
                await activateTrayItem(
                    with: .right,
                    actionName: "rightClick",
                    clickStartTime: clickStartTime,
                    itemManager: itemManager
                )
            }
        }
    }

    private func parkCursorAwayFromHotCorners() {
        guard
            let location = MouseHelpers.locationCoreGraphics,
            let parkingPoint = OverlayTrayHotCornerParkingPolicy.parkingPoint(
                for: location,
                screenFrames: NSScreen.screens.map { CGDisplayBounds($0.displayID) }
            )
        else {
            return
        }

        OverlayTrayItemView.diagLog.debug(
            """
            Parking cursor away from hot corner before dismissing tray: \
            from=(\(Int(location.x)),\(Int(location.y))) \
            to=(\(Int(parkingPoint.x)),\(Int(parkingPoint.y)))
            """
        )
        MouseHelpers.warpCursor(to: parkingPoint)
    }

    private func activateTrayItem(
        with mouseButton: CGMouseButton,
        actionName: String,
        clickStartTime: Date,
        itemManager: MenuBarItemManager
    ) async {
        let decision = await itemManager.activateItem(
            withIdentifier: item.uniqueIdentifier,
            on: displayID,
            mouseButton: mouseButton,
            fastPath: true
        )
        switch decision {
        case let .allow(route):
            logActivationCompletion(
                actionName: actionName,
                clickStartTime: clickStartTime,
                path: "\(route)"
            )
        case let .reject(reason):
            OverlayTrayItemView.diagLog.warning(
                "\(actionName): rejected activation for \(item.logString): \(reason)"
            )
        }
    }

    private func logActivationCompletion(
        actionName: String,
        clickStartTime: Date,
        path: String
    ) {
        let duration = Date.now.timeIntervalSince(clickStartTime)
        OverlayTrayItemView.diagLog.debug(
            "\(actionName): completed in \(Int(duration * 1000))ms (\(path))"
        )
    }

    private var image: NSImage? {
        guard let cachedImage = imageCache.images[item.tag] else {
            return nil
        }
        return cachedImage.nsImage
    }

    /// The owning application's icon, used when no captured pixel image is
    /// available. Continuum does not screen-capture menu bar items, so the
    /// image cache is always empty and this is the normal rendering path.
    private var fallbackIcon: NSImage? {
        if let pid = item.sourcePID,
           let app = NSRunningApplication(processIdentifier: pid),
           let icon = app.icon
        {
            return icon
        }
        if let bundleIdentifier = item.sourceApplication?.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    /// Square side for fallback icons, sized to sit comfortably within the
    /// tray's content height.
    private var iconSide: CGFloat {
        guard let maxHeight, maxHeight > 0 else { return 18 }
        return min(maxHeight - 8, 22)
    }

    private var clickTargetSize: CGSize {
        if let image {
            return targetSize(for: image)
        }
        return CGSize(width: iconSide + 10, height: maxHeight ?? iconSide)
    }

    private func targetSize(for image: NSImage) -> CGSize {
        let intrinsic = image.size
        guard intrinsic.height > 0 else {
            return intrinsic
        }

        guard let maxHeight, maxHeight > 0 else {
            return intrinsic
        }

        // Scale to fill the available height exactly. This handles both
        // directions: shrinking oversized captures (e.g. multi-monitor with
        // different scale factors) and growing undersized ones (e.g. 16"
        // MacBook Pro where the captured item height can be smaller than the
        // OverlayTray's content height derived from the full notch-area menu bar).
        let scale = maxHeight / intrinsic.height
        return CGSize(width: intrinsic.width * scale, height: maxHeight)
    }

    var body: some View {
        itemContent
            .background {
                RoundedRectangle(cornerRadius: pillCornerRadius, style: hasRoundedShape ? .circular : .continuous)
                    .fill((isLightBackground ? Color.black : Color.white).opacity(isHovered ? 0.15 : 0))
                    .padding(.vertical, 3)
            }
            .contentShape(Rectangle())
            .overlay {
                OverlayTrayItemClickView(
                    item: item,
                    tooltipDelay: tooltipDelay,
                    leftClickAction: leftClickAction,
                    rightClickAction: rightClickAction,
                    onHover: { hovering in
                        isHovered = hovering
                    }
                )
                .frame(width: clickTargetSize.width, height: clickTargetSize.height)
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .accessibilityLabel(item.displayName)
            .accessibilityAction(named: "left click", leftClickAction)
            .accessibilityAction(named: "right click", rightClickAction)
    }

    /// The item's visual. Prefers a captured pixel image when present; with
    /// screen capture removed that is never available, so the normal path is
    /// the owning app's icon, then a generic glyph. A non-zero size here is
    /// what gives the tray panel its width — without it every item collapses
    /// to nothing and the panel renders as a 1-2px sliver.
    /// SF Symbol for system modules (Wi-Fi, Bluetooth, Clock, …) so the tray
    /// shows a distinct glyph rather than the identical Control Center app icon.
    private var systemIcon: MenuBarSystemMenuExtraIcon? {
        MenuBarSystemMenuExtraMetadata.icon(for: item)
    }

    @ViewBuilder
    private var itemContent: some View {
        if let image {
            let size = targetSize(for: image)
            Image(nsImage: image)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .frame(width: size.width, height: size.height)
        } else if let systemIcon {
            SystemMenuExtraTrayIconView(icon: systemIcon, iconSide: iconSide, maxHeight: maxHeight)
                .padding(.horizontal, 5)
        } else if let fallbackIcon {
            Image(nsImage: fallbackIcon)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSide, height: iconSide)
                .frame(height: maxHeight, alignment: .center)
                .padding(.horizontal, 5)
        } else {
            Image(systemName: "circle.grid.2x2")
                .font(.system(size: iconSide * 0.62, weight: .medium))
                .frame(width: iconSide, height: maxHeight, alignment: .center)
                .padding(.horizontal, 5)
        }
    }
}

private struct SystemMenuExtraTrayIconView: View {
    let icon: MenuBarSystemMenuExtraIcon
    let iconSide: CGFloat
    let maxHeight: CGFloat?

    var body: some View {
        if let image = icon.nsImage {
            Image(nsImage: image)
                .renderingMode(.template)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSide, height: iconSide)
                .frame(height: maxHeight, alignment: .center)
        } else if let systemSymbolName = icon.systemSymbolName {
            Image(systemName: systemSymbolName)
                .font(.system(size: iconSide * 0.8, weight: .regular))
                .frame(width: iconSide, height: maxHeight, alignment: .center)
        }
    }
}

// MARK: - OverlayTrayItemClickView

enum OverlayTrayClickGesturePolicy {
    private static let maximumClickDuration: TimeInterval = 0.5
    private static let maximumClickMovement: CGFloat = 5

    static func shouldActivate(
        mouseDownDate: Date?,
        mouseDownLocation: CGPoint?,
        mouseUpDate: Date,
        mouseUpLocation: CGPoint,
        bounds: CGRect
    ) -> Bool {
        guard
            let mouseDownDate,
            let mouseDownLocation,
            bounds.contains(mouseDownLocation),
            bounds.contains(mouseUpLocation)
        else {
            return false
        }

        let duration = mouseUpDate.timeIntervalSince(mouseDownDate)
        return duration >= 0 &&
            duration < maximumClickDuration &&
            mouseDownLocation.distance(to: mouseUpLocation) < maximumClickMovement
    }
}

enum OverlayTrayHotCornerParkingPolicy {
    static func parkingPoint(
        for location: CGPoint,
        screenFrames: [CGRect]
    ) -> CGPoint? {
        let safePoint = MenuBarMoveGeometryPolicy.hotCornerSafePoint(
            location,
            screenFrames: screenFrames
        )
        return safePoint == location ? nil : safePoint
    }
}

private struct OverlayTrayItemClickView: NSViewRepresentable {
    final class Represented: NSView {
        var item: MenuBarItem
        var tooltipDelay: TimeInterval

        var leftClickAction: () -> Void
        var rightClickAction: () -> Void
        var onHover: (Bool) -> Void

        private var lastLeftMouseDownDate: Date?
        private var lastRightMouseDownDate: Date?

        private var lastLeftMouseDownLocation: CGPoint?
        private var lastRightMouseDownLocation: CGPoint?

        private lazy var tooltipController = CustomTooltipController(text: item.displayName, view: self)
        private var tooltipTrackingArea: NSTrackingArea?

        init(
            item: MenuBarItem,
            tooltipDelay: TimeInterval,
            leftClickAction: @escaping () -> Void,
            rightClickAction: @escaping () -> Void,
            onHover: @escaping (Bool) -> Void
        ) {
            self.item = item
            self.tooltipDelay = tooltipDelay
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            self.onHover = onHover
            super.init(frame: .zero)
        }

        func update(
            item: MenuBarItem,
            tooltipDelay: TimeInterval,
            leftClickAction: @escaping () -> Void,
            rightClickAction: @escaping () -> Void,
            onHover: @escaping (Bool) -> Void
        ) {
            self.item = item
            self.tooltipDelay = tooltipDelay
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            self.onHover = onHover
            tooltipController.text = item.displayName
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tooltipTrackingArea {
                removeTrackingArea(tooltipTrackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            tooltipTrackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            tooltipController.scheduleShow(delay: tooltipDelay)
            onHover(true)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            tooltipController.cancel()
            onHover(false)
        }

        override func mouseDown(with event: NSEvent) {
            tooltipController.cancel()
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else {
                lastLeftMouseDownDate = nil
                lastLeftMouseDownLocation = nil
                return
            }

            lastLeftMouseDownDate = .now
            lastLeftMouseDownLocation = location
        }

        override func rightMouseDown(with event: NSEvent) {
            tooltipController.cancel()
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else {
                lastRightMouseDownDate = nil
                lastRightMouseDownLocation = nil
                return
            }

            lastRightMouseDownDate = .now
            lastRightMouseDownLocation = location
        }

        override func mouseUp(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            let shouldActivate = OverlayTrayClickGesturePolicy.shouldActivate(
                mouseDownDate: lastLeftMouseDownDate,
                mouseDownLocation: lastLeftMouseDownLocation,
                mouseUpDate: .now,
                mouseUpLocation: location,
                bounds: bounds
            )
            lastLeftMouseDownDate = nil
            lastLeftMouseDownLocation = nil

            guard shouldActivate else {
                return
            }
            leftClickAction()
        }

        override func rightMouseUp(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            let shouldActivate = OverlayTrayClickGesturePolicy.shouldActivate(
                mouseDownDate: lastRightMouseDownDate,
                mouseDownLocation: lastRightMouseDownLocation,
                mouseUpDate: .now,
                mouseUpLocation: location,
                bounds: bounds
            )
            lastRightMouseDownDate = nil
            lastRightMouseDownLocation = nil

            guard shouldActivate else {
                return
            }
            rightClickAction()
        }
    }

    let item: MenuBarItem
    let tooltipDelay: TimeInterval

    let leftClickAction: () -> Void
    let rightClickAction: () -> Void
    let onHover: (Bool) -> Void

    func makeNSView(context _: Context) -> Represented {
        Represented(
            item: item,
            tooltipDelay: tooltipDelay,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction,
            onHover: onHover
        )
    }

    func updateNSView(_ nsView: Represented, context _: Context) {
        // Keep the backing `NSView` in sync with SwiftUI updates; tooltip text,
        // tooltip timing, and click handlers can all change after creation.
        nsView.update(
            item: item,
            tooltipDelay: tooltipDelay,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction,
            onHover: onHover
        )
    }
}
