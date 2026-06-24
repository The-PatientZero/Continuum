//
//  PermissionsView.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The standalone permissions screen: shows a card per required permission,
/// and Quit/Continue actions that gate first-launch setup.
struct PermissionsView<Manager: PermissionsManaging>: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var manager: Manager

    /// The continue button's label.
    private var continueButtonText: LocalizedStringKey {
        "Continue"
    }

    /// The continue button's foreground style, reflecting how complete the
    /// granted permissions are.
    private var continueButtonForegroundStyle: some ShapeStyle {
        switch manager.permissionsState {
        case .missing:
            AnyShapeStyle(.secondary)
        case .hasAll:
            AnyShapeStyle(.primary)
        case .hasRequired:
            AnyShapeStyle(.primary)
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            headerView

            permissionsStack

            footerView
        }
        .padding(24)
        .frame(width: 760, height: 600)
        .background(ContinuumDesign.Palette.surface)
        .tint(ContinuumDesign.Palette.accentForeground)
    }

    /// The title and reassurance copy shown above the permission cards.
    private var headerView: some View {
        VStack(spacing: 12) {
            Text("Enable Permissions")
                .font(.system(size: 34, weight: .semibold, design: .serif))

            VStack(spacing: 4) {
                Text("Almost there! \(Constants.displayName) needs the permissions below to manage your menu bar.")
                Text("Your data stays on your Mac — nothing is ever collected or shared.")
                    .foregroundStyle(.secondary)
            }
            .font(.body)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 500)
        }
    }

    /// A horizontal row of cards, one per permission the manager exposes.
    private var permissionsStack: some View {
        HStack(spacing: 16) {
            ForEach(manager.allPermissions) { permission in
                PermissionCard(permission: permission)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The Quit / Continue action row beneath the permission cards.
    private var footerView: some View {
        HStack(spacing: 12) {
            quitButton
            continueButton
        }
        .controlSize(.large)
    }

    /// Terminates the app outright — the only sound option when the user
    /// won't proceed through the mandatory first-launch permissions step.
    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Text("Quit")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    /// Completes first-launch setup with whatever permissions are currently
    /// granted. Disabled until at least the required permissions are in place.
    private var continueButton: some View {
        Button {
            appState.completeFirstLaunchSetup()
        } label: {
            Text(continueButtonText)
                .frame(maxWidth: .infinity)
                .foregroundStyle(continueButtonForegroundStyle)
        }
        .buttonStyle(.borderedProminent)
        .tint(ContinuumDesign.Palette.accent)
        .disabled(manager.permissionsState == .missing)
    }
}

// MARK: - PermissionCard

/// A card describing a single permission — its icon, title, details, and a
/// button to request it (or a confirmation once it's been granted).
struct PermissionCard: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var permission: Permission
    @State var isRequestingPermission = false

    /// Whether granting the permission should bring the permissions window
    /// back to the front. Disabled when hosted in a context — like the
    /// onboarding tour's replay preview — that shouldn't steal focus.
    var refocusesWindowAfterGrant = true

    var body: some View {
        ContinuumSection {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(permission.title)
                        .font(.title2.weight(.semibold))
                } icon: {
                    Image(systemName: permission.iconName)
                        .font(.title2)
                        .foregroundStyle(permission.iconColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(permission.details, id: \.self) { detail in
                        Label {
                            Text(detail)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.callout)

                Spacer(minLength: 0)

                Button {
                    guard !isRequestingPermission else {
                        return
                    }
                    isRequestingPermission = true
                    permission.performRequest()
                    Task {
                        defer { isRequestingPermission = false }
                        await permission.waitForPermission()
                        appState.activate(withPolicy: .regular)
                        if refocusesWindowAfterGrant {
                            appState.openWindow(.permissions)
                        }
                    }
                } label: {
                    if permission.hasPermission {
                        Label("Permission Granted", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Grant Permission")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(permission.hasPermission ? ContinuumDesign.Palette.success : ContinuumDesign.Palette.accent)
                .allowsHitTesting(!permission.hasPermission)
                .disabled(isRequestingPermission)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// A lightweight stand-in for ``AppPermissions`` used by the preview, so it
/// doesn't need to spin up the real manager and its app machinery.
private final class MockPermissionsManager: PermissionsManaging {
    @Published var permissionsState: AppPermissions.PermissionsState = .missing

    let allPermissions: [Permission] = [
        AccessibilityPermission(),
    ]
}

#Preview {
    PermissionsView<MockPermissionsManager>()
        .environmentObject(AppState())
        .environmentObject(MockPermissionsManager())
}
