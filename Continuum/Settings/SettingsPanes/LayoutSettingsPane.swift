//
//  LayoutSettingsPane.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

private enum LayoutEditorMetrics {
    static let laneWidth: CGFloat = 220
    static let laneSpacing: CGFloat = 14
    static let noticeWidth: CGFloat = laneWidth * 3 + laneSpacing * 2
    static let rowHeight: CGFloat = 46
    static let iconSize: CGFloat = 30
    static let cornerRadius: CGFloat = ContinuumDesign.Radius.lg
    static let rowCornerRadius: CGFloat = ContinuumDesign.Radius.md
    static let hairline: CGFloat = ContinuumDesign.Hairline.width
}

private typealias LayoutEditorPalette = ContinuumDesign.Palette

private enum LayoutEditorCoordinateSpace {
    static let name = "LayoutEditorCoordinateSpace"
}

private struct LayoutInsertionTarget: Equatable {
    let section: MenuBarSection.Name
    let beforeItemID: String?
}

private struct LayoutRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct LayoutLaneFramePreferenceKey: PreferenceKey {
    static let defaultValue: [MenuBarSection.Name: CGRect] = [:]

    static func reduce(
        value: inout [MenuBarSection.Name: CGRect],
        nextValue: () -> [MenuBarSection.Name: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct LayoutDraft: Equatable {
    var sections: [MenuBarSection.Name: [MenuBarLayoutEditorItem]]

    static let empty = LayoutDraft(
        sections: Dictionary(uniqueKeysWithValues: MenuBarSection.Name.allCases.map { ($0, []) })
    )

    var order: [MenuBarSection.Name: [String]] {
        Dictionary(uniqueKeysWithValues: MenuBarSection.Name.allCases.map { section in
            (section, sections[section, default: []].map(\.id))
        })
    }
}

struct LayoutSettingsPane: View {
    @ObservedObject var itemManager: MenuBarItemManager

    @State private var draft = LayoutDraft.empty
    @State private var baselineOrder = LayoutDraft.empty.order
    @State private var targetedSection: MenuBarSection.Name?
    @State private var targetedItemID: String?
    @State private var draggingItemID: String?
    @State private var insertionTarget: LayoutInsertionTarget?
    @State private var rowFrames = [String: CGRect]()
    @State private var laneFrames = [MenuBarSection.Name: CGRect]()
    @State private var isSaving = false
    @State private var isRefreshing = false
    @State private var didSave = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasChanges: Bool {
        draft.order != baselineOrder
    }

    private var itemCount: Int {
        draft.sections.values.reduce(0) { $0 + $1.count }
    }

    private var hasPendingIdentities: Bool {
        draft.sections.values.flatMap { $0 }.contains { item in
            item.isAvailable && !item.isIdentityResolved
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    if hasPendingIdentities {
                        identityNotice
                    }

                    HStack(alignment: .top, spacing: LayoutEditorMetrics.laneSpacing) {
                        ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                            lane(for: section)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
            .coordinateSpace(name: LayoutEditorCoordinateSpace.name)
            .background(LayoutEditorPalette.surface)
            .onPreferenceChange(LayoutRowFramePreferenceKey.self) { rowFrames = $0 }
            .onPreferenceChange(LayoutLaneFramePreferenceKey.self) { laneFrames = $0 }

            footer
        }
        .tint(LayoutEditorPalette.accentForeground)
        .frame(minWidth: 760, minHeight: 500)
        .onAppear {
            reloadFromManager()
            refreshFromLiveMenuBar()
        }
        .onChange(of: itemManager.itemCache) { _, _ in
            guard !hasChanges else { return }
            reloadFromManager()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LayoutEditorPalette.accent.opacity(0.22))
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LayoutEditorPalette.accentForeground)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Layout")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                Text(layoutStatusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LayoutEditorPalette.textTertiary)
            }

            Spacer(minLength: 16)

            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            } else if didSave {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LayoutEditorPalette.success)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if hasChanges {
                Label("Staged", systemImage: "circle.dashed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LayoutEditorPalette.accentForeground)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(LayoutEditorPalette.raised)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LayoutEditorPalette.hairline)
                .frame(height: LayoutEditorMetrics.hairline)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(itemCount) items")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LayoutEditorPalette.textTertiary)

            Spacer()

            Button {
                reloadFromManager()
                refreshFromLiveMenuBar()
            } label: {
                Label("Revert", systemImage: "arrow.uturn.backward")
            }
            .disabled(!hasChanges || isSaving)

            Button {
                saveLayout()
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Save Layout", systemImage: "checkmark")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(LayoutEditorPalette.accent)
            .disabled(!hasChanges || isSaving)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(LayoutEditorPalette.raised)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LayoutEditorPalette.hairline)
                .frame(height: LayoutEditorMetrics.hairline)
        }
    }

    private var identityNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LayoutEditorPalette.accent.opacity(0.16))
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LayoutEditorPalette.accentForeground)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text("Identifying menu extras")
                    .font(.system(size: 12, weight: .semibold))
                Text("Some menu extras are still being identified. You can stage them now; Save Layout applies the order, and names refresh when macOS reports the owning app.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LayoutEditorPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: LayoutEditorMetrics.noticeWidth, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: LayoutEditorMetrics.cornerRadius, style: .continuous)
                .fill(LayoutEditorPalette.raised)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LayoutEditorMetrics.cornerRadius, style: .continuous)
                .strokeBorder(LayoutEditorPalette.accent.opacity(0.24), lineWidth: LayoutEditorMetrics.hairline)
        }
    }

    private var layoutStatusText: String {
        if isRefreshing {
            return "Refreshing menu bar items"
        }
        if hasChanges {
            return "Changes are waiting to be saved"
        }
        return "Current menu bar arrangement"
    }

    private func lane(for section: MenuBarSection.Name) -> some View {
        let items = draft.sections[section, default: []]
        let isTargeted = targetedSection == section || insertionTarget?.section == section

        return VStack(alignment: .leading, spacing: 10) {
            laneHeader(for: section, count: items.count)

            VStack(spacing: 7) {
                if insertionTarget?.section == section, insertionTarget?.beforeItemID == items.first?.id {
                    insertionLine(for: section)
                }

                if items.isEmpty {
                    emptyLane(for: section)
                } else {
                    ForEach(items) { item in
                        if insertionTarget?.section == section,
                           insertionTarget?.beforeItemID == item.id,
                           insertionTarget?.beforeItemID != items.first?.id
                        {
                            insertionLine(for: section)
                        }
                        itemRow(item, in: section)
                    }
                }

                if insertionTarget?.section == section, insertionTarget?.beforeItemID == nil, draggingItemID != nil {
                    insertionLine(for: section)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 244, alignment: .top)
        }
        .padding(12)
        .frame(width: LayoutEditorMetrics.laneWidth, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: LayoutEditorMetrics.cornerRadius, style: .continuous)
                .fill(LayoutEditorPalette.raised)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LayoutEditorMetrics.cornerRadius, style: .continuous)
                .strokeBorder(
                    laneBorderColor(for: section, isTargeted: isTargeted),
                    lineWidth: isTargeted ? 1.4 : LayoutEditorMetrics.hairline
                )
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LayoutLaneFramePreferenceKey.self,
                    value: [section: proxy.frame(in: .named(LayoutEditorCoordinateSpace.name))]
                )
            }
        }
    }

    private func laneHeader(for section: MenuBarSection.Name, count: Int) -> some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(sectionAccent(section).opacity(0.14))
                Image(systemName: sectionSymbol(section))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(sectionAccent(section))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(sectionTitle(section))
                    .font(.system(size: 13, weight: .semibold))
                Text(sectionCaption(section))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LayoutEditorPalette.textTertiary)
            }

            Spacer()

            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(LayoutEditorPalette.textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(LayoutEditorPalette.surface, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(LayoutEditorPalette.hairline, lineWidth: LayoutEditorMetrics.hairline)
                }
        }
    }

    @ViewBuilder
    private func itemRow(
        _ item: MenuBarLayoutEditorItem,
        in section: MenuBarSection.Name
    ) -> some View {
        let row = itemRowBody(item, in: section)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: LayoutRowFramePreferenceKey.self,
                        value: [item.id: proxy.frame(in: .named(LayoutEditorCoordinateSpace.name))]
                    )
                }
            }

        if item.isMovable {
            // highPriorityGesture, not gesture: the rows live inside a vertical
            // ScrollView, and a plain .gesture loses the drag to the scroll
            // view's own pan recognizer. When the scroll view claims the drag
            // mid-gesture, DragGesture.onEnded never fires, so draggingItemID
            // stays set and the row appears "frozen" while a fresh drag on
            // another row still works. Taking high priority lets the row's
            // drag win so the gesture completes and state resets cleanly.
            // Vertical scrolling still works by dragging empty lane space.
            row.highPriorityGesture(dragGesture(for: item))
        } else {
            row
        }
    }

    private func itemRowBody(
        _ item: MenuBarLayoutEditorItem,
        in section: MenuBarSection.Name
    ) -> some View {
        HStack(spacing: 10) {
            itemGlyph(for: item, section: section)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(item.isAvailable ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(item.subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LayoutEditorPalette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            Image(systemName: item.isMovable ? "line.3.horizontal" : "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.isMovable ? LayoutEditorPalette.textTertiary : .secondary)
                .frame(width: 18, height: 18)
                .help(item.isMovable ? "Drag to stage this item" : "This item cannot be moved by macOS")
        }
        .padding(.horizontal, 10)
        .frame(height: LayoutEditorMetrics.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: LayoutEditorMetrics.rowCornerRadius, style: .continuous)
                .fill(rowFill(for: item))
        }
        .overlay {
            RoundedRectangle(cornerRadius: LayoutEditorMetrics.rowCornerRadius, style: .continuous)
                .strokeBorder(
                    targetedItemID == item.id ? sectionAccent(section).opacity(0.78) : LayoutEditorPalette.hairline,
                    lineWidth: targetedItemID == item.id ? 1.2 : LayoutEditorMetrics.hairline
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: LayoutEditorMetrics.rowCornerRadius, style: .continuous))
        .scaleEffect(draggingItemID == item.id ? 0.985 : 1)
        .shadow(
            color: .black.opacity(draggingItemID == item.id ? 0.14 : 0),
            radius: draggingItemID == item.id ? 8 : 0,
            y: draggingItemID == item.id ? 4 : 0
        )
        .zIndex(draggingItemID == item.id ? 1 : 0)
        .opacity(item.isMovable ? (draggingItemID == item.id ? 0.58 : 1) : 0.76)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
    }

    private func insertionLine(for section: MenuBarSection.Name) -> some View {
        Capsule()
            .fill(sectionAccent(section).opacity(0.86))
            .frame(height: 2)
            .padding(.horizontal, 8)
            .shadow(color: sectionAccent(section).opacity(0.18), radius: 3, y: 1)
            .transition(.opacity)
    }

    private func itemGlyph(
        for item: MenuBarLayoutEditorItem,
        section: MenuBarSection.Name
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(sectionAccent(section).opacity(item.isAvailable ? 0.14 : 0.07))
            if let systemIcon = item.systemIcon {
                SystemMenuExtraIconView(
                    icon: systemIcon,
                    color: sectionAccent(section),
                    size: 20,
                    symbolPointSize: 14
                )
            } else if item.isIdentityResolved {
                if let image = iconImage(for: item) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(sectionAccent(section))
                }
            } else {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(sectionAccent(section))
            }
        }
        .frame(width: LayoutEditorMetrics.iconSize, height: LayoutEditorMetrics.iconSize)
        .overlay(alignment: .bottomTrailing) {
            if !item.isIdentityResolved {
                Circle()
                    .fill(LayoutEditorPalette.accentForeground)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(LayoutEditorPalette.raised, lineWidth: 1.2))
                    .offset(x: 2, y: 2)
            }
        }
    }

    private func emptyLane(for section: MenuBarSection.Name) -> some View {
        VStack(spacing: 8) {
            Image(systemName: sectionSymbol(section))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(sectionAccent(section).opacity(0.55))
            Text("No items")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LayoutEditorPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 156)
        .background {
            RoundedRectangle(cornerRadius: LayoutEditorMetrics.rowCornerRadius, style: .continuous)
                .fill(LayoutEditorPalette.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LayoutEditorMetrics.rowCornerRadius, style: .continuous)
                .strokeBorder(
                    LayoutEditorPalette.hairline,
                    style: StrokeStyle(lineWidth: LayoutEditorMetrics.hairline, dash: [5, 4])
                )
        }
    }

    private func reloadFromManager() {
        let snapshot = itemManager.layoutEditorSnapshot()
        draft = LayoutDraft(sections: snapshot.sections)
        baselineOrder = draft.order
        didSave = false
    }

    private func refreshFromLiveMenuBar() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task { @MainActor in
            await itemManager.refreshLayoutEditorCache()
            guard !hasChanges else {
                isRefreshing = false
                return
            }
            reloadFromManager()
            isRefreshing = false
        }
    }

    private func saveLayout() {
        guard hasChanges, !isSaving else { return }
        isSaving = true
        didSave = false

        let order = draft.order
        Task { @MainActor in
            await itemManager.applyLayoutEditorOrder(order)
            baselineOrder = order
            refreshFromLiveMenuBar()
            isSaving = false
            withAnimation(layoutAnimation) {
                didSave = true
            }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(layoutAnimation) {
                didSave = false
            }
        }
    }

    private func moveItem(
        _ identifier: String,
        to targetSection: MenuBarSection.Name,
        before targetIdentifier: String?
    ) -> Bool {
        guard targetIdentifier != identifier else { return false }
        guard !itemPlacementMatches(identifier, targetSection: targetSection, before: targetIdentifier) else {
            return false
        }

        guard let source = removeItem(identifier) else { return false }
        guard source.item.isMovable else {
            draft.sections[source.section, default: []].insert(source.item, at: source.index)
            return false
        }

        var targetItems = draft.sections[targetSection, default: []]
        let targetIndex: Int
        if let targetIdentifier,
           let index = targetItems.firstIndex(where: { $0.id == targetIdentifier }),
           targetIdentifier != identifier
        {
            targetIndex = index
        } else {
            targetIndex = targetItems.endIndex
        }

        targetItems.insert(source.item, at: targetIndex)
        draft.sections[targetSection] = targetItems

        withAnimation(layoutAnimation) {
            didSave = false
        }
        return true
    }

    private func dragGesture(for item: MenuBarLayoutEditorItem) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(LayoutEditorCoordinateSpace.name))
            .onChanged { value in
                guard item.isMovable else { return }
                if draggingItemID == nil {
                    draggingItemID = item.id
                }
                updateDragTarget(for: item.id, at: value.location)
            }
            .onEnded { _ in
                withAnimation(layoutAnimation) {
                    draggingItemID = nil
                    targetedSection = nil
                    targetedItemID = nil
                    insertionTarget = nil
                }
            }
    }

    private func updateDragTarget(for identifier: String, at location: CGPoint) {
        let targetSection = section(at: location, fallbackFor: identifier)
        let targetIdentifier = insertionIdentifier(in: targetSection, at: location, excluding: identifier)
        let target = LayoutInsertionTarget(section: targetSection, beforeItemID: targetIdentifier)

        withAnimation(layoutAnimation) {
            targetedSection = targetSection
            targetedItemID = targetIdentifier
            insertionTarget = target
            _ = moveItem(identifier, to: targetSection, before: targetIdentifier)
        }
    }

    private func section(at location: CGPoint, fallbackFor identifier: String) -> MenuBarSection.Name {
        let horizontalPadding = LayoutEditorMetrics.laneSpacing / 2
        let containingSection = laneFrames
            .filter { _, frame in
                location.x >= frame.minX - horizontalPadding && location.x <= frame.maxX + horizontalPadding
            }
            .min { lhs, rhs in
                abs(lhs.value.midX - location.x) < abs(rhs.value.midX - location.x)
            }?
            .key

        if let containingSection {
            return containingSection
        }

        if let nearestSection = laneFrames.min(by: {
            abs($0.value.midX - location.x) < abs($1.value.midX - location.x)
        })?.key {
            return nearestSection
        }

        return itemLocation(identifier)?.section ?? .visible
    }

    private func insertionIdentifier(
        in section: MenuBarSection.Name,
        at location: CGPoint,
        excluding identifier: String
    ) -> String? {
        let items = draft.sections[section, default: []].filter { $0.id != identifier }
        for item in items {
            guard let frame = rowFrames[item.id] else { continue }
            if location.y < frame.midY {
                return item.id
            }
        }
        return nil
    }

    private func itemPlacementMatches(
        _ identifier: String,
        targetSection: MenuBarSection.Name,
        before targetIdentifier: String?
    ) -> Bool {
        guard let source = itemLocation(identifier), source.section == targetSection else {
            return false
        }

        let identifiers = draft.sections[targetSection, default: []].map(\.id)
        let nextIdentifier = identifiers.dropFirst(source.index + 1).first
        if let targetIdentifier {
            return nextIdentifier == targetIdentifier
        }
        return source.index == identifiers.count - 1
    }

    private func itemLocation(
        _ identifier: String
    ) -> (section: MenuBarSection.Name, index: Int)? {
        for section in MenuBarSection.Name.allCases {
            let items = draft.sections[section, default: []]
            guard let index = items.firstIndex(where: { $0.id == identifier }) else { continue }
            return (section, index)
        }
        return nil
    }

    private func removeItem(
        _ identifier: String
    ) -> (item: MenuBarLayoutEditorItem, section: MenuBarSection.Name, index: Int)? {
        for section in MenuBarSection.Name.allCases {
            var items = draft.sections[section, default: []]
            guard let index = items.firstIndex(where: { $0.id == identifier }) else { continue }
            let item = items.remove(at: index)
            draft.sections[section] = items
            return (item, section, index)
        }
        return nil
    }

    private var layoutAnimation: Animation? {
        reduceMotion ? nil : .timingCurve(0.25, 1, 0.5, 1, duration: 0.18)
    }

    private func laneBorderColor(for section: MenuBarSection.Name, isTargeted: Bool) -> Color {
        isTargeted ? sectionAccent(section).opacity(0.72) : LayoutEditorPalette.hairline
    }

    private func rowFill(for item: MenuBarLayoutEditorItem) -> Color {
        item.isAvailable ? LayoutEditorPalette.surface.opacity(0.82) : Color.secondary.opacity(0.06)
    }

    private func sectionTitle(_ section: MenuBarSection.Name) -> LocalizedStringKey {
        switch section {
        case .visible: "Visible"
        case .hidden: "Tray"
        case .alwaysHidden: "Always Hidden"
        }
    }

    private func sectionCaption(_ section: MenuBarSection.Name) -> LocalizedStringKey {
        switch section {
        case .visible: "Menu bar"
        case .hidden: "Overlay"
        case .alwaysHidden: "Reserved"
        }
    }

    private func sectionSymbol(_ section: MenuBarSection.Name) -> String {
        switch section {
        case .visible: "menubar.rectangle"
        case .hidden: "tray"
        case .alwaysHidden: "eye.slash"
        }
    }

    private func sectionAccent(_ section: MenuBarSection.Name) -> Color {
        switch section {
        case .visible: LayoutEditorPalette.visibleAccent
        case .hidden: LayoutEditorPalette.trayAccent
        case .alwaysHidden: LayoutEditorPalette.reservedAccent
        }
    }

    private func iconImage(for item: MenuBarLayoutEditorItem) -> NSImage? {
        if let pid = item.iconProcessIdentifier,
           let runningApplication = NSRunningApplication(processIdentifier: pid),
           let icon = runningApplication.icon
        {
            return icon
        }

        if let bundleIdentifier = item.iconBundleIdentifier,
           let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            return NSWorkspace.shared.icon(forFile: applicationURL.path)
        }

        return nil
    }
}

private struct SystemMenuExtraIconView: View {
    let icon: MenuBarSystemMenuExtraIcon
    let color: Color
    let size: CGFloat
    let symbolPointSize: CGFloat

    var body: some View {
        if let image = icon.nsImage {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(color)
        } else if let systemSymbolName = icon.systemSymbolName {
            Image(systemName: systemSymbolName)
                .font(.system(size: symbolPointSize, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}
