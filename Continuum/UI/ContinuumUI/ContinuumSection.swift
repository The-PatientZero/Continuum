//
//  ContinuumSection.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct ContinuumSectionOptions: OptionSet {
    let rawValue: Int

    static let isBordered = ContinuumSectionOptions(rawValue: 1 << 0)
    static let hasDividers = ContinuumSectionOptions(rawValue: 1 << 1)

    static let plain: ContinuumSectionOptions = []
    static let defaultValue: ContinuumSectionOptions = [.isBordered, .hasDividers]
}

struct ContinuumSection<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer
    private let spacing: CGFloat
    private let options: ContinuumSectionOptions

    private var isBordered: Bool {
        options.contains(.isBordered)
    }

    private var hasDividers: Bool {
        options.contains(.hasDividers)
    }

    init(
        spacing: CGFloat = .continuumSectionDefaultSpacing,
        options: ContinuumSectionOptions = .defaultValue,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.spacing = spacing
        self.options = options
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    init(
        spacing: CGFloat = .continuumSectionDefaultSpacing,
        options: ContinuumSectionOptions = .defaultValue,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        self.init(spacing: spacing, options: options) {
            EmptyView()
        } content: {
            content()
        } footer: {
            footer()
        }
    }

    init(
        spacing: CGFloat = .continuumSectionDefaultSpacing,
        options: ContinuumSectionOptions = .defaultValue,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init(spacing: spacing, options: options) {
            header()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        spacing: CGFloat = .continuumSectionDefaultSpacing,
        options: ContinuumSectionOptions = .defaultValue,
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView, Footer == EmptyView {
        self.init(spacing: spacing, options: options) {
            EmptyView()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        _ title: LocalizedStringKey,
        spacing: CGFloat = .continuumSectionDefaultSpacing,
        options: ContinuumSectionOptions = .defaultValue,
        @ViewBuilder content: () -> Content
    ) where Header == Text, Footer == EmptyView {
        self.init(spacing: spacing, options: options) {
            Text(title)
                .font(.system(size: ContinuumDesign.TypeScale.body, weight: .semibold))
        } content: {
            content()
        }
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                headerView

                if isBordered {
                    ContinuumGroupBox(padding: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)) {
                        contentLayout
                    }
                } else {
                    contentLayout
                }

                footerView
            }
        }
    }

    @ViewBuilder
    private var contentLayout: some View {
        if hasDividers {
            _VariadicView.Tree(ContinuumSectionLayout(spacing: spacing)) {
                content.frame(maxWidth: .infinity)
            }
        } else {
            content.frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var headerView: some View {
        if Header.self != EmptyView.self {
            header
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, 8)
                .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        if Footer.self != EmptyView.self {
            footer
                .padding([.bottom, .leading], 8)
                .padding(.top, 2)
        }
    }
}

// MARK: - ContinuumSectionLayout

private struct ContinuumSectionLayout: _VariadicView_UnaryViewRoot {
    let spacing: CGFloat

    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(children) { child in
                child
                    .transition(.opacity.combined(with: .scale(scale: 0.98))) // Smooth Tahoe-style transitions

                if child.id != last {
                    ContinuumSectionDivider()
                }
            }
        }
        .padding(8)
    }
}

// MARK: - ContinuumSectionDivider

private struct ContinuumSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(ContinuumDesign.Palette.hairline)
            .frame(height: ContinuumDesign.Hairline.width)
            .padding(.horizontal, 4)
    }
}

extension CGFloat {
    /// The default spacing for an ``ContinuumSection``.
    static let continuumSectionDefaultSpacing: CGFloat = 8
}
