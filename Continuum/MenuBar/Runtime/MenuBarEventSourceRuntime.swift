//
//  MenuBarEventSourceRuntime.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@preconcurrency import CoreGraphics
import os.lock

/// Thread-safe CoreGraphics event-source cache and suppression setup for
/// synthetic menu-bar interactions.
enum MenuBarEventSourceRuntime {
    private enum Cache {
        static let sources = OSAllocatedUnfairLock(initialState: [CGEventSourceStateID: CGEventSource]())
    }

    static func source(
        with stateID: CGEventSourceStateID = .hidSystemState
    ) throws -> CGEventSource {
        if let source = Cache.sources.withLock({ $0[stateID] }) {
            return source
        }

        guard let source = CGEventSource(stateID: stateID) else {
            throw MenuBarEventError.invalidEventSource
        }
        Cache.sources.withLock { $0[stateID] = source }
        return source
    }

    static func permitLocalEvents() throws {
        let source = try source(with: .combinedSessionState)
        let states: [CGEventSuppressionState] = [
            .eventSuppressionStateRemoteMouseDrag,
            .eventSuppressionStateSuppressionInterval,
        ]
        for state in states {
            source.setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: state)
        }
        source.localEventsSuppressionInterval = 0
    }
}
