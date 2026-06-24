//
//  ContinuumColor.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// A custom color.
struct ContinuumColor: Hashable {
    /// The color, represented as a `CGColor`.
    var cgColor: CGColor
}

// MARK: - ContinuumDesign

enum ContinuumDesign {
    enum Space {
        static let hair: CGFloat = 3
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let xxxl: CGFloat = 24
    }

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 9
        static let lg: CGFloat = 13
        static let window: CGFloat = 18
    }

    enum Hairline {
        static let width: CGFloat = 0.5
    }

    enum TypeScale {
        static let micro: CGFloat = 10
        static let caption: CGFloat = 11
        static let control: CGFloat = 12
        static let body: CGFloat = 13
        static let input: CGFloat = 14
        static let title: CGFloat = 16
        static let stat: CGFloat = 20
        static let display: CGFloat = 24
    }

    enum Palette {
        static let accent = Color(red: 0.984, green: 0.749, blue: 0.141)
        static let accentForeground = Color.continuumDynamic(light: 0x826312, dark: 0xFBBF24)
        static let onAccent = Color(red: 0.102, green: 0.098, blue: 0.086)

        static let surface = Color.continuumDynamic(light: 0xF6F2EC, dark: 0x1A1916)
        static let raised = Color.continuumDynamic(light: 0xFCF9F4, dark: 0x232220)
        static let hairline = Color.continuumDynamic(light: 0xE7E0D5, dark: 0x33302B)
        static let textTertiary = Color.continuumDynamic(light: 0x6E665A, dark: 0x9C948A)

        static let success = Color.continuumDynamic(light: 0x2F855A, dark: 0x48BB78)
        static let danger = Color.continuumDynamic(light: 0xC2371F, dark: 0xFF6B5A)

        static let visibleAccent = Color.continuumDynamic(light: 0x0A7066, dark: 0x2DD4BF)
        static let trayAccent = Color.continuumDynamic(light: 0x5C6A7F, dark: 0x94A3B8)
        static let reservedAccent = Color.continuumDynamic(light: 0xB24A22, dark: 0xF08A5D)
    }
}

extension Color {
    /// Resolves to `light` in Aqua and `dark` in Dark Aqua; both values are packed `0xRRGGBB`.
    static func continuumDynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: .continuumDynamic(light: light, dark: dark))
    }
}

extension NSColor {
    convenience init(continuumRGB rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    static func continuumDynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(continuumRGB: isDark ? dark : light)
        }
    }
}

// MARK: ContinuumColor: Codable

extension ContinuumColor: Codable {
    private enum CodingKeys: CodingKey {
        case components
        case colorSpace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var components = try container.decode([CGFloat].self, forKey: .components)
        let iccData = try container.decode(Data.self, forKey: .colorSpace) as CFData
        guard let colorSpace = CGColorSpace(iccData: iccData) else {
            throw DecodingError.dataCorruptedError(
                forKey: .colorSpace,
                in: container,
                debugDescription: "Invalid ICC profile data"
            )
        }
        guard let cgColor = CGColor(colorSpace: colorSpace, components: &components) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid color space or components"
                )
            )
        }
        self.cgColor = cgColor
    }

    func encode(to encoder: Encoder) throws {
        guard let components = cgColor.components else {
            throw EncodingError.invalidValue(
                cgColor,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Missing color components"
                )
            )
        }
        guard let colorSpace = cgColor.colorSpace else {
            throw EncodingError.invalidValue(
                cgColor,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Missing color space"
                )
            )
        }
        guard let iccData = colorSpace.copyICCData() else {
            throw EncodingError.invalidValue(
                colorSpace,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Missing ICC profile data"
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(components, forKey: .components)
        try container.encode(iccData as Data, forKey: .colorSpace)
    }
}
