//
//  OnboardingMockups.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - Shared desktop pieces

/// A blue gradient backdrop that stands in for the user's desktop wallpaper
/// behind the demo menu bar.
private struct DesktopBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0x6E / 255, green: 0xAB / 255, blue: 0xEF / 255),
                Color(red: 0x3E / 255, green: 0x5A / 255, blue: 0xC1 / 255),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
/// Menu bar tint and label colors that mirror how the real macOS menu bar
/// switches between a translucent dark material (dark mode) and a
/// translucent light material (light mode).
struct MenuBarTint {
    let colorScheme: ColorScheme

    /// The translucent material color behind the demo menu bar.
    var background: Color {
        colorScheme == .dark ? Color.black.opacity(0.5) : Color.white.opacity(0.6)
    }

    /// The color used for icons and text drawn on top of the menu bar.
    var label: Color {
        colorScheme == .dark ? .white : .black
    }
}

/// The leading "apple.logo" + app name pairing that mirrors the left side of
/// the real macOS menu bar. An optional `tint` overrides the color derived
/// from the current ``MenuBarTint``, e.g. when drawn over a colored bar style.
private struct AppMenuLabels: View {
    @Environment(\.colorScheme) private var colorScheme
    var tint: Color?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "apple.logo")
                .font(.system(size: 11))
            Text(verbatim: "Finder")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle((tint ?? MenuBarTint(colorScheme: colorScheme).label).opacity(0.75))
        .padding(.leading, 12)
    }
}

/// The demo menu bar status items, split into the symbols that live in the
/// hidden section (left of the divider) and the always-visible ones. Shared by
/// the management and hotkeys mockups so both tell the same story.
enum MenuBarDemoItems {
    static let hidden = ["wifi", "battery.100", "speaker.wave.2"]
}

/// Mirrors the rightmost native macOS menu bar items — Control Center, then
/// the clock — so every mockup ends on the same recognizable anchor. The
/// clock shows only the hour and minute, matching a 24-hour-style reading
/// without the AM/PM suffix.
private struct MenuBarClockGroup: View {
    let tint: Color

    private var timeString: String {
        Date.now.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "switch.2")
                .font(.system(size: 10))
            Text(timeString)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint)
    }
}

/// A horizontal row of menu bar status icons rendered at the shared demo size.
private struct MenuBarIconRow: View {
    let symbols: [String]
    let color: Color
    var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(symbols, id: \.self) { sym in
                Image(systemName: sym).font(.system(size: 10))
            }
        }
        .foregroundStyle(color)
    }
}

/// The Continuum control-item divider, styled after the "Dot" ControlIcon
/// (DotFill / DotStroke) — a small filled circle between menu bar sections.
private struct MenuBarDividerDot: View {
    @Environment(\.colorScheme) private var colorScheme
    var tint: Color?

    var body: some View {
        Circle()
            .fill(tint ?? MenuBarTint(colorScheme: colorScheme).label)
            .frame(width: 6, height: 6)
    }
}

/// Dark capsule HUD for interactive controls overlaid on the desktop (not zoomed).
struct ControlHUD<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
    }
}

/// Runs `action` on the main queue after `seconds` have elapsed.
@MainActor
func delay(_ seconds: Double, action: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
}

/// Drives the scripted, auto-playing animation steps of a mockup. Each call to
/// `restart()` bumps a generation token; steps scheduled against an older token
/// are silently dropped, so re-entering a slide cleanly cancels any animation
/// still in flight from a previous visit.
@MainActor
final class MockupTimeline {
    private var generation = 0

    @discardableResult
    func restart() -> Int {
        generation += 1
        return generation
    }

    /// Runs `action` after `seconds`, unless the timeline has restarted since
    /// `generation` was captured.
    func schedule(after seconds: Double, generation gen: Int, _ action: @escaping @MainActor () -> Void) {
        delay(seconds) { [weak self] in
            guard let self, self.generation == gen else { return }
            action()
        }
    }
}

/// Where — and how far — a slide's mockup zooms into its MacBook screen.
/// `corner` is expressed in the zoomed view's own unit coordinates
/// (0,0 = top-leading, 1,1 = bottom-trailing) and names the feature the
/// camera should push into.
struct OnboardingZoomSpec {
    var scale: CGFloat
    var corner: UnitPoint

    static let none = OnboardingZoomSpec(scale: 1, corner: .center)

    /// The MacBook zooms in once, on the first feature slide, and then holds
    /// that framing for the rest of the tour — only the screen content and HUD
    /// crossfade between slides, so a single shared target keeps the laptop
    /// from jumping around.
    static let featureTour = OnboardingZoomSpec(scale: 2.0, corner: UnitPoint(x: 1.1, y: 0.0))
}

/// Zooms a view into a target corner by scaling about that corner. Anchoring
/// the scale at the target point — rather than scaling from the center and
/// translating afterwards — keeps that point in place as everything around it
/// grows, which guarantees the zoomed content always fully covers the frame
/// (translating a centered zoom toward an off-center point would instead drag
/// the content's far edge into view, exposing the background behind it).
extension View {
    func zoomingIntoCorner(_ zoomed: Bool, scale: CGFloat, corner: UnitPoint) -> some View {
        scaleEffect(zoomed ? scale : 1.0, anchor: corner)
            .animation(.spring(duration: 0.7, bounce: 0.1), value: zoomed)
    }
}

// MARK: - Welcome

/// The opening slide's mockup: just the app icon, scaling and fading in on
/// appearance.
struct OnboardingWelcomeMockup: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 132, height: 132)
                    .shadow(color: .black.opacity(0.4), radius: 28, y: 14)
                    .scaleEffect(appear ? 1 : 0.85)
                    .opacity(appear ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) { appear = true }
        }
    }
}

// MARK: - Menu Bar Management

//
// Zooms into the right side of the menu bar. The Continuum capsule divider is the
// tappable toggle — matching ControlItem.HidingState going from
// .hideSection → .showSection. Hidden items (left of divider) fade + slide
// when hidden. The HUD label below floats outside the laptop and stays put
// while the screen zooms in around the divider.

/// Drives the menu bar management slide: starts with the demo items hidden,
/// then automatically reveals them, mirroring `ControlItem.HidingState`
/// going from `.hideSection` to `.showSection`.
@MainActor
final class ManagementMockupModel: ObservableObject {
    /// Whether the demo's hidden-section items are currently tucked away.
    @Published var itemsHidden = true
    private let timeline = MockupTimeline()

    /// Resets to the hidden state, then schedules the automatic reveal.
    func restart() {
        let gen = timeline.restart()
        itemsHidden = true
        timeline.schedule(after: 1.10, generation: gen) { [weak self] in
            withAnimation(.spring(duration: 0.45)) { self?.itemsHidden = false }
        }
    }

    /// Flips the hidden/visible state, as if the divider had been clicked.
    func toggle() {
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) { itemsHidden.toggle() }
    }
}

/// Renders the demo menu bar for the management slide, with a tappable
/// divider dot that hides or reveals the demo's status items.
struct ManagementScreen: View {
    @ObservedObject var model: ManagementMockupModel
    @Environment(\.colorScheme) private var colorScheme

    private var tint: MenuBarTint {
        MenuBarTint(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .top) {
            DesktopBackground()
            menuBar
        }
    }

    private var menuBar: some View {
        HStack(spacing: 0) {
            AppMenuLabels()
            Spacer()

            MenuBarIconRow(symbols: MenuBarDemoItems.hidden, color: tint.label.opacity(0.85))
                .opacity(model.itemsHidden ? 0 : 1)
                .offset(x: model.itemsHidden ? 16 : 0)
                .animation(.spring(duration: 0.45, bounce: 0.1), value: model.itemsHidden)
                .padding(.trailing, 8)

            Button {
                model.toggle()
            } label: {
                ZStack {
                    Color.clear.frame(width: 22, height: 24)
                    MenuBarDividerDot(tint: tint.label.opacity(0.85))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 2)

            MenuBarClockGroup(tint: tint.label.opacity(0.9))
                .padding(.trailing, 8)
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(tint.background)
    }
}

/// The floating capsule label for the management slide, naming the action
/// ("Show"/"Hide") that the next automatic step will perform.
struct ManagementHUD: View {
    @ObservedObject var model: ManagementMockupModel

    var body: some View {
        ControlHUD {
            Label(
                model.itemsHidden ?
                    String(localized: "onboarding.mockup.management.show") :
                    String(localized: "onboarding.mockup.management.hide"),
                systemImage: "hand.tap"
            )
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.85))
            .animation(nil, value: model.itemsHidden)
        }
    }
}
