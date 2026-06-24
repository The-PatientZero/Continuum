//
//  MenuBarEventContinuationRuntime.swift
//  Project: Continuum
//
//  Copyright © 2023–2025 Jordan Baird
//  Copyright © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@preconcurrency import CoreGraphics
import os.lock

/// Delivery mode for synthetic menu-bar events that need EventTap feedback.
enum MenuBarEventContinuationMode: Equatable {
    case postEventBarrier
    case scromble

    var requiresFirstLocationRelayTap: Bool {
        self == .scromble
    }

    func operationTimeout(base: Duration, repeatCount: Int) -> Duration {
        base * repeatCount
    }
}

/// Runs the low-level EventTap relay used to post synthetic menu-bar events
/// and wait until the target process has observed them.
enum MenuBarEventContinuationRuntime {
    private struct Context {
        let event: CGEvent
        let pid: pid_t
        let entryEvent: CGEvent
        let exitEvent: CGEvent
        let firstLocation: EventTap.Location
        let secondLocation: EventTap.Location
    }

    private struct State {
        let countHolder: OSAllocatedUnfairLock<Int>
        let didResume: OSAllocatedUnfairLock<Bool>
        let continuationHolder: OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>
        let innerTaskHolder: OSAllocatedUnfairLock<Task<Void, Never>?>
    }

    static func perform(
        mode: MenuBarEventContinuationMode,
        event: CGEvent,
        item: MenuBarItem,
        pid: pid_t,
        timeout: Duration,
        repeating count: Int
    ) async throws {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        guard
            let entryEvent = CGEvent.uniqueNullEvent(),
            let exitEvent = CGEvent.uniqueNullEvent()
        else {
            throw MenuBarEventError.eventCreationFailure(item)
        }

        event.setTargetPID(pid)

        let firstLocation = EventTap.Location.pid(pid)
        let secondLocation = EventTap.Location.sessionEventTap
        let state = State(
            countHolder: OSAllocatedUnfairLock(initialState: count),
            didResume: OSAllocatedUnfairLock(initialState: false),
            continuationHolder: OSAllocatedUnfairLock(initialState: nil),
            innerTaskHolder: OSAllocatedUnfairLock(initialState: nil)
        )
        let context = Context(
            event: event,
            pid: pid,
            entryEvent: entryEvent,
            exitEvent: exitEvent,
            firstLocation: firstLocation,
            secondLocation: secondLocation
        )

        let timeoutTask = Task(timeout: mode.operationTimeout(base: timeout, repeatCount: count)) {
            var eventTaps = [EventTap]()
            defer {
                for tap in eventTaps {
                    tap.invalidate()
                }
            }
            try await withTaskCancellationHandler {
                try await awaitContinuation(
                    mode: mode,
                    context: context,
                    state: state,
                    eventTaps: &eventTaps
                )
            } onCancel: {
                currentInnerTask(from: state.innerTaskHolder)?.cancel()
                let continuation = currentContinuation(from: state.continuationHolder)
                if let continuation, state.didResume.tryClaimOnce() {
                    continuation.resume(throwing: CancellationError())
                }
            }
        }

        do {
            try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw MenuBarEventError.eventOperationTimeout(item)
        } catch {
            throw MenuBarEventError.cannotComplete
        }
    }

    private static func storeContinuation(
        _ continuation: CheckedContinuation<Void, any Error>,
        in holder: OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>
    ) {
        holder.withLock { $0 = continuation }
    }

    private static func storeInnerTask(
        _ task: Task<Void, Never>,
        in holder: OSAllocatedUnfairLock<Task<Void, Never>?>
    ) {
        holder.withLock { $0 = task }
    }

    private static func currentContinuation(
        from holder: OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>
    ) -> CheckedContinuation<Void, any Error>? {
        holder.withLock { $0 }
    }

    private static func currentInnerTask(
        from holder: OSAllocatedUnfairLock<Task<Void, Never>?>
    ) -> Task<Void, Never>? {
        holder.withLock { $0 }
    }

    private static func decrementCount(
        in holder: OSAllocatedUnfairLock<Int>
    ) -> Int {
        holder.withLock {
            $0 -= 1
            return $0
        }
    }

    private static func currentCount(
        from holder: OSAllocatedUnfairLock<Int>
    ) -> Int {
        holder.withLock { $0 }
    }

    private static func makeContinuationTask(
        eventTaps: [EventTap],
        entryEvent: CGEvent,
        firstLocation: EventTap.Location
    ) -> Task<Void, Never> {
        Task {
            for eventTap in eventTaps {
                eventTap.enable()
            }
            entryEvent.post(to: firstLocation)
        }
    }

    private static func makeEventTap(
        label: String,
        type: CGEventType,
        location: EventTap.Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions,
        handler: @escaping (EventTap, CGEvent) -> CGEvent?
    ) -> EventTap {
        EventTap(
            label: label,
            type: type,
            location: location,
            placement: placement,
            option: option,
            callback: handler
        )
    }

    private static func makeMenuBarItemEventTap(
        label: String,
        location: EventTap.Location,
        placement: CGEventTapPlacement,
        context: Context,
        onMatch: @escaping (EventTap) -> Void
    ) -> EventTap {
        makeEventTap(
            label: label,
            type: context.event.type,
            location: location,
            placement: placement,
            option: .listenOnly
        ) { tap, receivedEvent in
            guard receivedEvent.matches(
                context.event,
                byIntegerFields: CGEventField.menuBarItemEventFields
            ) else {
                return receivedEvent
            }
            onMatch(tap)
            // Defensive: listen-only taps cannot affect the system stream, but
            // keeping the target PID aligned preserves parity with the old path.
            receivedEvent.setTargetPID(context.pid)
            return receivedEvent
        }
    }

    private static func makeEntryEventTap(
        context: Context,
        state: State,
        continuation: CheckedContinuation<Void, any Error>
    ) -> EventTap {
        makeEventTap(
            label: "EventTap 1",
            type: .null,
            location: context.firstLocation,
            placement: .headInsertEventTap,
            option: .defaultTap
        ) { tap, receivedEvent in
            if receivedEvent.matches(context.entryEvent, byIntegerFields: [.eventSourceUserData]) {
                _ = decrementCount(in: state.countHolder)
                context.event.post(to: context.secondLocation)
                return nil
            }
            if receivedEvent.matches(context.exitEvent, byIntegerFields: [.eventSourceUserData]) {
                tap.disable()
                if state.didResume.tryClaimOnce() {
                    continuation.resume()
                }
                return nil
            }
            return receivedEvent
        }
    }

    private static func makeSecondLocationEventTap(
        mode: MenuBarEventContinuationMode,
        context: Context,
        state: State
    ) -> EventTap {
        makeMenuBarItemEventTap(
            label: "EventTap 2",
            location: context.secondLocation,
            placement: .tailAppendEventTap,
            context: context
        ) { tap in
            switch mode {
            case .postEventBarrier:
                if currentCount(from: state.countHolder) <= 0 {
                    tap.disable()
                    context.exitEvent.post(to: context.firstLocation)
                } else {
                    context.entryEvent.post(to: context.firstLocation)
                }
            case .scromble:
                if currentCount(from: state.countHolder) <= 0 {
                    tap.disable()
                }
                context.event.post(to: context.firstLocation)
            }
        }
    }

    private static func makeFirstLocationRelayEventTap(
        context: Context,
        state: State
    ) -> EventTap {
        makeMenuBarItemEventTap(
            label: "EventTap 3",
            location: context.firstLocation,
            placement: .headInsertEventTap,
            context: context
        ) { tap in
            if currentCount(from: state.countHolder) <= 0 {
                tap.disable()
                context.exitEvent.post(to: context.firstLocation)
            } else {
                context.entryEvent.post(to: context.firstLocation)
            }
        }
    }

    private static func makeEventTaps(
        mode: MenuBarEventContinuationMode,
        context: Context,
        state: State,
        continuation: CheckedContinuation<Void, any Error>
    ) -> [EventTap] {
        var eventTaps = [
            makeEntryEventTap(
                context: context,
                state: state,
                continuation: continuation
            ),
            makeSecondLocationEventTap(
                mode: mode,
                context: context,
                state: state
            ),
        ]
        if mode.requiresFirstLocationRelayTap {
            eventTaps.append(
                makeFirstLocationRelayEventTap(
                    context: context,
                    state: state
                )
            )
        }
        return eventTaps
    }

    private static func awaitContinuation(
        mode: MenuBarEventContinuationMode,
        context: Context,
        state: State,
        eventTaps: inout [EventTap]
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            storeContinuation(continuation, in: state.continuationHolder)

            let continuationEventTaps = makeEventTaps(
                mode: mode,
                context: context,
                state: state,
                continuation: continuation
            )
            eventTaps.append(contentsOf: continuationEventTaps)

            let innerTask = makeContinuationTask(
                eventTaps: continuationEventTaps,
                entryEvent: context.entryEvent,
                firstLocation: context.firstLocation
            )
            storeInnerTask(innerTask, in: state.innerTaskHolder)
            if Task.isCancelled {
                innerTask.cancel()
            }
        }
    }
}
