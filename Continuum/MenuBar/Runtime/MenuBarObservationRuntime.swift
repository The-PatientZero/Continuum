//
//  MenuBarObservationRuntime.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Builds a normalized, optionally identity-reconciled menu bar observation.
///
/// WindowServer reads are noisy: they can briefly return no menu-bar items,
/// include transient clone windows, or report a stale source process after a
/// move. Keeping that normalization in one runtime boundary prevents unstable
/// input from leaking directly into relocation, saved-layout, reset, restore,
/// and cache planning.
enum MenuBarObservationRuntime {
    typealias ItemProvider = (_ resolveSourcePID: Bool) async -> [MenuBarItem]
    typealias Sleeper = (_ duration: Duration) async -> Void

    struct Result {
        let observation: MenuBarObservationFrame
        let attempts: Int
        let identityCorrections: [MenuBarIdentityReconciler.Correction]
        let identifiersToSeed: Set<String>

        var items: [MenuBarItem] {
            observation.items
        }
    }

    struct ZeroItemFailure: Equatable {
        let detail: String
        let attempts: Int
    }

    enum Outcome {
        case observed(Result)
        case zeroItems(ZeroItemFailure)
    }

    @MainActor
    static func observe(
        displayID: CGDirectDisplayID?,
        currentItemWindowIDs: [CGWindowID]? = nil,
        previousWindowIDs: [CGWindowID] = [],
        previousSourcePIDs: [CGWindowID: pid_t] = [:],
        knownItemIdentifiers: Set<String> = [],
        resolveSourcePID: Bool,
        itemProvider: ItemProvider,
        sleeper: @escaping Sleeper = { duration in
            try? await Task.sleep(for: duration)
        },
        bundleIdentifierForPID: (pid_t) -> String? = { _ in nil }
    ) async -> Outcome {
        var attempts = 1
        var rawItems = [MenuBarItem]()

        observationLoop: while true {
            rawItems = await itemProvider(resolveSourcePID)

            switch MenuBarObservationRetryPolicy.evaluate(
                observedItemCount: rawItems.count,
                attempt: attempts
            ) {
            case .accept:
                break observationLoop
            case let .retry(delay):
                await sleeper(delay)
                attempts += 1
            case let .fail(detail):
                return .zeroItems(ZeroItemFailure(detail: detail, attempts: attempts))
            }
        }

        var observation = MenuBarObservationFrame.filteringSystemClones(
            displayID: displayID,
            rawItems: rawItems,
            currentItemWindowIDs: currentItemWindowIDs
        )

        let reconciliation: MenuBarIdentityReconciler.Result
        if resolveSourcePID, !previousSourcePIDs.isEmpty {
            reconciliation = MenuBarIdentityReconciler.reconcile(
                items: observation.items,
                previousSourcePIDs: previousSourcePIDs,
                bundleIdentifierForPID: bundleIdentifierForPID
            )
        } else {
            reconciliation = MenuBarIdentityReconciler.Result(
                items: observation.items,
                corrections: []
            )
        }
        observation = observation.replacingItems(reconciliation.items)

        let identifiersToSeed = MenuBarKnownItemIdentifierPolicy.identifiersToSeedAfterIdentityCorrection(
            observation: observation,
            previousWindowIDs: previousWindowIDs,
            knownItemIdentifiers: knownItemIdentifiers
        )

        return .observed(
            Result(
                observation: observation,
                attempts: attempts,
                identityCorrections: reconciliation.corrections,
                identifiersToSeed: identifiersToSeed
            )
        )
    }
}
