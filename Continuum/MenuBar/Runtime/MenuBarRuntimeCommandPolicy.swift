//
//  MenuBarRuntimeCommandPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Pure command-admission policy for identifier-addressed menu bar actions.
///
/// Stable local control flows resolve an exact item identifier before mutating:
/// callers inspect inventory, resolve the exact identifier, then this policy
/// decides whether the runtime can safely execute the command against the
/// current snapshot.
enum MenuBarRuntimeCommandPolicy {
    enum ActivationDecision: Equatable {
        case allow(MenuBarClickTargetPolicy.ActivationRoute)
        case reject(RejectionReason)
    }

    enum RejectionReason: Equatable, CustomStringConvertible {
        case itemNotFound(String)
        case liveItemUnavailable(String)
        case runtimeNotActionable(MenuBarRuntimeRecoveryAction)
        case automatedMoveUnavailable(MenuBarIdentityConfidence)
        case invalidIdentity(MenuBarIdentityConfidence)

        var description: String {
            switch self {
            case let .itemNotFound(identifier):
                "itemNotFound(\(identifier))"
            case let .liveItemUnavailable(identifier):
                "liveItemUnavailable(\(identifier))"
            case let .runtimeNotActionable(action):
                "runtimeNotActionable(recommendedRecovery=\(action))"
            case let .automatedMoveUnavailable(confidence):
                "automatedMoveUnavailable(\(confidence))"
            case let .invalidIdentity(confidence):
                "invalidIdentity(\(confidence))"
            }
        }
    }

    static func activationDecision(
        itemIdentifier: String,
        inventory: MenuBarRuntimeInventory,
        itemIsOnScreen: Bool
    ) -> ActivationDecision {
        guard let item = inventory.item(withIdentifier: itemIdentifier) else {
            return .reject(.itemNotFound(itemIdentifier))
        }
        if inventory.snapshot.systemMenuBarHidden {
            return .reject(
                .runtimeNotActionable(inventory.recommendedRecoveryAction)
            )
        }

        let route = MenuBarClickTargetPolicy.activationRoute(
            itemIsOnScreen: itemIsOnScreen
        )

        switch route {
        case .clickInPlace:
            guard allowsDirectActivation(item.confidence) else {
                return .reject(.invalidIdentity(item.confidence))
            }
        case .temporarilyReveal:
            guard inventory.isActionable else {
                return .reject(
                    .runtimeNotActionable(inventory.recommendedRecoveryAction)
                )
            }
            guard allowsTemporaryReveal(item.confidence) else {
                return .reject(.invalidIdentity(item.confidence))
            }
            guard item.allowsAutomatedMove else {
                return .reject(.automatedMoveUnavailable(item.confidence))
            }
        }

        return .allow(route)
    }

    static func liveItem(
        withIdentifier identifier: String,
        in cache: MenuBarItemCache
    ) -> MenuBarItem? {
        cache.managedItems.first { $0.uniqueIdentifier == identifier }
    }

    private static func allowsDirectActivation(
        _ confidence: MenuBarIdentityConfidence
    ) -> Bool {
        switch confidence {
        case .stable, .titleOnly:
            true
        case .structural, .unresolved, .transient, .invalid:
            false
        }
    }

    private static func allowsTemporaryReveal(
        _ confidence: MenuBarIdentityConfidence
    ) -> Bool {
        confidence == .stable
    }
}
