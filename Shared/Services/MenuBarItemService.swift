//
//  MenuBarItemService.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

enum MenuBarItemService {
    static let name = "com.thepatientzero.Continuum.MenuBarItemService"
}

extension MenuBarItemService {
    enum Request: Codable {
        case start
        case configureLogging(filePath: String)
        case sourcePID(WindowInfo)
        case sourcePIDs([WindowInfo])
    }

    enum Response: Codable {
        case start
        case configureLogging
        case sourcePID(pid_t?)
        case sourcePIDs([pid_t?])
    }
}
