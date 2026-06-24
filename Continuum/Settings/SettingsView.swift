//
//  SettingsView.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    let appState: AppState
    @ObservedObject var navigationState: AppNavigationState

    private var allSections: [SettingsNavigationIdentifier] {
        SettingsNavigationIdentifier.visibleCases
    }

    private var displayedSection: SettingsNavigationIdentifier {
        guard allSections.contains(navigationState.settingsNavigationIdentifier) else {
            return .general
        }
        return navigationState.settingsNavigationIdentifier
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            settingsPane
                .id(displayedSection)
                .background(ContinuumDesign.Palette.surface)
        }
        .navigationTitle(displayedSection.localized)
        .tint(ContinuumDesign.Palette.accentForeground)
    }

    private var sidebar: some View {
        // Use a Binding that wraps the navigation state to ensure updates happen
        // on the main thread and avoid view update warnings.
        let selection = Binding<SettingsNavigationIdentifier>(
            get: { displayedSection },
            set: { newValue in
                if navigationState.settingsNavigationIdentifier != newValue {
                    Task { @MainActor in
                        navigationState.settingsNavigationIdentifier = newValue
                    }
                }
            }
        )

        return List(selection: selection) {
            Section {
                ForEach(allSections) { identifier in
                    Label {
                        Text(identifier.localized)
                    } icon: {
                        identifier.iconResource.view
                    }
                    .tag(identifier)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(ideal: 180, max: 220)
    }

    @ViewBuilder
    private var settingsPane: some View {
        switch displayedSection {
        case .general:
            GeneralSettingsPane(settings: appState.settings.general)
        case .layout:
            LayoutSettingsPane(itemManager: appState.itemManager)
        case .about:
            AboutSettingsPane(updatesManager: appState.updatesManager)
        }
    }
}
