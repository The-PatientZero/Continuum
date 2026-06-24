//
//  MenuBarSectionTransitionPolicy.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// Pure section-transition policy for saved-layout apply.
///
/// The manager owns fresh WindowServer observations and move execution. This
/// policy owns the hidden/always-hidden set arithmetic so cross-section moves
/// and fallback ordering stay deterministic under menu-bar churn.
enum MenuBarSectionTransitionPolicy {
    struct SectionObservation: Equatable {
        let uniqueIdentifier: String
        let windowID: CGWindowID
        let isLayoutItem: Bool
    }

    struct AnchorObservation: Equatable {
        let uniqueIdentifier: String
        let isMovable: Bool
    }

    struct SectionSets: Equatable {
        let currentHidden: Set<String>
        let currentAlwaysHidden: Set<String>
        let desiredHidden: Set<String>
        let desiredAlwaysHidden: Set<String>
        let desiredVisible: Set<String>
    }

    struct Assessment: Equatable {
        let sets: SectionSets
        let wrongInHidden: Set<String>
        let wrongInAlwaysHidden: Set<String>
        let needsHiddenMove: Set<String>
        let needsAlwaysHiddenMove: Set<String>

        var crossSectionMoveCount: Int {
            wrongInHidden.count + wrongInAlwaysHidden.count
        }

        var totalSectionMismatch: Int {
            needsHiddenMove.count + needsAlwaysHiddenMove.count
        }

        var requiresAlwaysHiddenControlMove: Bool {
            crossSectionMoveCount > 0 || totalSectionMismatch > 0
        }
    }

    struct FallbackPlan: Equatable {
        let toAlwaysHidden: Set<String>
        let toHidden: Set<String>
        let orderedToAlwaysHidden: [String]
        let orderedToHidden: [String]

        var hasMoves: Bool {
            !toAlwaysHidden.isEmpty || !toHidden.isEmpty
        }

        var moves: [FallbackMove] {
            orderedToAlwaysHidden.map {
                FallbackMove(
                    uniqueIdentifier: $0,
                    destination: .leftOfAlwaysHiddenControl
                )
            } + orderedToHidden.map {
                FallbackMove(
                    uniqueIdentifier: $0,
                    destination: .rightOfAlwaysHiddenControl
                )
            }
        }
    }

    struct AlwaysHiddenControlMovePlan: Equatable {
        let controlUID: String
        let anchorCandidates: [String]
    }

    struct FallbackMove: Equatable {
        let uniqueIdentifier: String
        let destination: FallbackDestination
    }

    enum FallbackDestination: Equatable {
        case leftOfAlwaysHiddenControl
        case rightOfAlwaysHiddenControl

        var diagnosticName: String {
            switch self {
            case .leftOfAlwaysHiddenControl:
                "AH"
            case .rightOfAlwaysHiddenControl:
                "hidden"
            }
        }
    }

    static func sectionSets(
        observations: [SectionObservation],
        sectionByWindowID: [CGWindowID: MenuBarSection.Name],
        itemOrder: [String: [String]]
    ) -> SectionSets {
        var currentHidden = Set<String>()
        var currentAlwaysHidden = Set<String>()

        for observation in observations where observation.isLayoutItem {
            switch sectionByWindowID[observation.windowID] {
            case .hidden:
                currentHidden.insert(observation.uniqueIdentifier)
            case .alwaysHidden:
                currentAlwaysHidden.insert(observation.uniqueIdentifier)
            case .visible, nil:
                break
            }
        }

        return SectionSets(
            currentHidden: currentHidden,
            currentAlwaysHidden: currentAlwaysHidden,
            desiredHidden: Set(identifiers(in: .hidden, itemOrder: itemOrder)),
            desiredAlwaysHidden: Set(identifiers(in: .alwaysHidden, itemOrder: itemOrder)),
            desiredVisible: Set(identifiers(in: .visible, itemOrder: itemOrder))
        )
    }

    static func alwaysHiddenControlMovePlan(
        assessment: Assessment,
        itemOrder: [String: [String]],
        hiddenControlUID: String,
        alwaysHiddenControlUID: String?
    ) -> AlwaysHiddenControlMovePlan? {
        guard assessment.requiresAlwaysHiddenControlMove, let alwaysHiddenControlUID else {
            return nil
        }
        return AlwaysHiddenControlMovePlan(
            controlUID: alwaysHiddenControlUID,
            anchorCandidates: alwaysHiddenControlAnchorCandidates(
                itemOrder: itemOrder,
                hiddenControlUID: hiddenControlUID
            )
        )
    }

    static func resolvedAlwaysHiddenControlAnchorUID(
        for plan: AlwaysHiddenControlMovePlan,
        anchors: [AnchorObservation],
        hiddenControlUID: String
    ) -> String? {
        for candidateUID in plan.anchorCandidates {
            guard let anchor = anchors.first(where: { $0.uniqueIdentifier == candidateUID }) else {
                continue
            }
            if candidateUID == hiddenControlUID || anchor.isMovable {
                return candidateUID
            }
        }
        return nil
    }

    static func assess(_ sets: SectionSets) -> Assessment {
        let wrongInHidden = sets.currentHidden
            .subtracting(sets.desiredHidden)
            .intersection(sets.desiredAlwaysHidden)
        let wrongInAlwaysHidden = sets.currentAlwaysHidden
            .subtracting(sets.desiredAlwaysHidden)
            .intersection(sets.desiredHidden)
        return Assessment(
            sets: sets,
            wrongInHidden: wrongInHidden,
            wrongInAlwaysHidden: wrongInAlwaysHidden,
            needsHiddenMove: sets.currentAlwaysHidden.intersection(sets.desiredHidden),
            needsAlwaysHiddenMove: sets.currentHidden.intersection(sets.desiredAlwaysHidden)
        )
    }

    static func alwaysHiddenControlAnchorCandidates(
        itemOrder: [String: [String]],
        hiddenControlUID: String
    ) -> [String] {
        if let firstHiddenUID = identifiers(in: .hidden, itemOrder: itemOrder).first {
            return [firstHiddenUID, hiddenControlUID]
        }
        return [hiddenControlUID]
    }

    static func fallbackPlan(
        currentHidden: Set<String>,
        currentAlwaysHidden: Set<String>,
        itemOrder: [String: [String]]
    ) -> FallbackPlan {
        let desiredAlwaysHidden = identifiers(in: .alwaysHidden, itemOrder: itemOrder)
        let desiredHidden = identifiers(in: .hidden, itemOrder: itemOrder)
        let toAlwaysHidden = currentHidden.intersection(desiredAlwaysHidden)
        let toHidden = currentAlwaysHidden.intersection(desiredHidden)

        return FallbackPlan(
            toAlwaysHidden: toAlwaysHidden,
            toHidden: toHidden,
            orderedToAlwaysHidden: orderedForAlwaysHiddenMove(
                toAlwaysHidden,
                savedOrder: desiredAlwaysHidden
            ),
            orderedToHidden: orderedForHiddenMove(
                toHidden,
                savedOrder: desiredHidden
            )
        )
    }

    private static func identifiers(
        in section: MenuBarSection.Name,
        itemOrder: [String: [String]]
    ) -> [String] {
        itemOrder[section.rawValue] ?? []
    }

    private static func orderedForAlwaysHiddenMove(
        _ identifiers: Set<String>,
        savedOrder: [String]
    ) -> [String] {
        savedOrder.reversed().filter { identifiers.contains($0) } +
            identifiers.subtracting(savedOrder).sorted()
    }

    private static func orderedForHiddenMove(
        _ identifiers: Set<String>,
        savedOrder: [String]
    ) -> [String] {
        savedOrder.filter { identifiers.contains($0) } +
            identifiers.subtracting(savedOrder).sorted()
    }
}
