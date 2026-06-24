//
//  OnboardingPageIndicator.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A row of capsule dots marking progress through the onboarding tour, with
/// the current page drawn wider and in the accent color.
struct OnboardingPageIndicator: View {
    /// The number of dots to display.
    let totalPages: Int
    /// The zero-based index of the page to highlight.
    let currentPage: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage
                          ? ContinuumDesign.Palette.accentForeground
                          : ContinuumDesign.Palette.textTertiary.opacity(0.28))
                    .frame(width: index == currentPage ? 18 : 6, height: 6)
                    .animation(.snappy, value: currentPage)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Page \(currentPage + 1) of \(totalPages)"))
    }
}
