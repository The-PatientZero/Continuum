//
//  GeneralSettingsPane.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@preconcurrency import LaunchAtLogin
import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: GeneralSettings
    @State private var isImportingCustomControlIcon = false
    @State private var isPresentingError = false
    @State private var presentedError: LocalizedErrorWrapper?

    var body: some View {
        ContinuumForm {
            ContinuumSection {
                appOptions
            }
            ContinuumSection {
                controlIconOptions
            }
        }
    }

    // MARK: App Options

    private var appOptions: some View {
        LaunchAtLogin.Toggle {
            Text("Launch at Login")
        }
    }

    // MARK: Control Icon Options

    @ViewBuilder
    private var controlIconOptions: some View {
        showControlIcon
        if settings.showControlIcon {
            controlIconPicker
        }
    }

    private var showControlIcon: some View {
        Toggle("Show \(Constants.displayName) icon", isOn: $settings.showControlIcon)
            .annotation("Show the \(Constants.displayName) icon in the menu bar. Click to show hidden items and right-click for settings.")
    }

    @ViewBuilder
    private var controlIconPicker: some View {
        let labelKey: LocalizedStringKey = "\(Constants.displayName) icon"

        ContinuumMenu(labelKey) {
            Picker(labelKey, selection: $settings.controlIcon) {
                ForEach(ControlItemImageSet.userSelectableControlIcons) { imageSet in
                    Button {
                        settings.controlIcon = imageSet
                    } label: {
                        controlIconMenuItem(for: imageSet)
                    }
                    .tag(imageSet)
                }
                if let lastCustomControlIcon = settings.lastCustomControlIcon {
                    Button {
                        settings.controlIcon = lastCustomControlIcon
                    } label: {
                        controlIconMenuItem(for: lastCustomControlIcon)
                    }
                    .tag(lastCustomControlIcon)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Button("Choose image…") {
                isImportingCustomControlIcon = true
            }
        } title: {
            controlIconMenuItem(for: settings.controlIcon)
        }
        .annotation("Choose a custom icon to show in the menu bar.")
        .fileImporter(
            isPresented: $isImportingCustomControlIcon,
            allowedContentTypes: [.image]
        ) { result in
            do {
                let url = try result.get()
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    settings.controlIcon = ControlItemImageSet(name: .custom, image: .data(data))
                }
            } catch {
                presentedError = LocalizedErrorWrapper(error)
                isPresentingError = true
            }
        }
        .alert(isPresented: $isPresentingError, error: presentedError) {
            Button("OK") {
                presentedError = nil
                isPresentingError = false
            }
        }

        if case .custom = settings.controlIcon.name {
            Toggle("Custom icon uses dynamic appearance", isOn: $settings.customControlIconIsTemplate)
                .annotation {
                    Text(
                        """
                        Display the icon as a monochrome image that dynamically adjusts to match \
                        the menu bar's appearance. This setting removes all color from the icon, \
                        but ensures consistent rendering with both light and dark backgrounds.
                        """
                    )
                    .padding(.trailing, 50)
                }
        }
    }

    private func controlIconMenuItem(for imageSet: ControlItemImageSet) -> some View {
        Label {
            Text(imageSet.name.localized)
        } icon: {
            if let nsImage = imageSet.hidden.nsImage(for: appState) {
                if imageSet.name == .custom {
                    Image(size: CGSize(width: 18, height: 18)) { context in
                        context.draw(Image(nsImage: nsImage), in: context.clipBoundingRect)
                    }
                } else {
                    Image(nsImage: nsImage)
                }
            }
        }
    }
}
