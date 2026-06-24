//
//  ContinuumForm.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct ContinuumForm<Content: View>: View {
    @State private var contentFrame = CGRect.zero

    private let alignment: HorizontalAlignment
    private let padding: EdgeInsets
    private let spacing: CGFloat
    private let content: Content

    init(
        alignment: HorizontalAlignment = .center,
        padding: EdgeInsets = .continuumFormDefaultPadding,
        spacing: CGFloat = .continuumFormDefaultSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.padding = padding
        self.spacing = spacing
        self.content = content()
    }

    init(
        alignment: HorizontalAlignment = .center,
        padding: CGFloat,
        spacing: CGFloat = .continuumFormDefaultSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            alignment: alignment,
            padding: EdgeInsets(all: padding),
            spacing: spacing
        ) {
            content()
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                contentLayout.frame(
                    minWidth: geometry.size.width,
                    minHeight: geometry.size.height,
                    alignment: .top
                )
            }
            .background(ContinuumDesign.Palette.surface)
            .scrollContentBackground(.hidden)
        }
        .focusSection()
        .accessibilityElement(children: .contain)
    }

    private var contentLayout: some View {
        VStack(alignment: alignment, spacing: spacing) {
            content
        }
        .labeledContentStyle(ContinuumFormLabeledContentStyle())
        .toggleStyle(ContinuumFormToggleStyle())
        .padding(padding)
        .onFrameChange(update: $contentFrame)
    }
}

private struct ContinuumFormLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        LabeledContent {
            configuration.content
                .layoutPriority(1)
        } label: {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)
        }
    }
}

private struct ContinuumFormToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(ContinuumDesign.Palette.accentForeground)
    }
}

extension EdgeInsets {
    /// The default padding for an ``ContinuumForm``.
    static let continuumFormDefaultPadding: EdgeInsets = .init(top: 0, leading: 20, bottom: 20, trailing: 20)
}

extension CGFloat {
    /// The default spacing for an ``ContinuumForm``.
    static let continuumFormDefaultSpacing: CGFloat = 24
}
