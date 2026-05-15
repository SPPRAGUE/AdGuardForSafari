// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  PopupStore.swift
//  PopupExtension
//

import Foundation
import AML

// MARK: - PopupStore

/// Single owner of `Store.State`. Serializes all `Store.Action`
/// dispatches through the actor, runs the reducer, and feeds
/// resulting effects to `EffectRunner`. Completion actions from
/// effects are dispatched back into the store.
///
/// `snapshot()` provides a synchronous, non-actor read of the
/// current state for `ToolbarRenderer`.
/// ToolbarRenderer is called by Safari synchronously — it cannot
/// `await` actor-isolated properties. Therefore `snapshot()` is
/// `nonisolated` and reads a lock-protected copy outside actor
/// isolation.
actor PopupStore {
    // MARK: - Properties

    private var state: Store.State
    private let effectRunner: EffectRunning

    /// Lock-protected copy of state for synchronous `snapshot()`.
    /// Uses `UnfairLock` from AML (heap-allocated `os_unfair_lock`
    /// wrapper conforming to `NSLocking`).
    nonisolated(unsafe) private let lock = UnfairLock()
    nonisolated(unsafe) private var snapshotState: Store.State

    /// Continuations for active `subscribe()` consumers.
    private var continuations: [UUID: AsyncStream<Store.State>.Continuation] = [:]

    // MARK: - Init

    init(
        initialState: Store.State = .initial,
        effectRunner: EffectRunning
    ) {
        self.state = initialState
        self.effectRunner = effectRunner
        self.snapshotState = initialState
    }

    deinit {
        for continuation in self.continuations.values {
            continuation.finish()
        }
    }

    // MARK: - Public API

    /// Dispatch an action. The reducer runs synchronously on the
    /// actor; effects are fired concurrently. Completion actions
    /// from effects are dispatched back into the store.
    func dispatch(_ action: Store.Action) {
        let (nextState, effects) = PopupReducer.reduce(
            state: self.state,
            action: action
        )

        if nextState != self.state {
            self.state = nextState
            self.publishSnapshot(nextState)
            for continuation in self.continuations.values {
                continuation.yield(nextState)
            }
        }

        for effect in effects {
            let task = Task {
                if let completionAction = await self.effectRunner.run(effect) {
                    self.dispatch(completionAction)
                }
            }
            self.effectRunner.registerTask(task, for: effect)
        }
    }

    /// Returns a new stream of state changes. Each subscriber
    /// receives all subsequent updates independently.
    func subscribe() -> AsyncStream<Store.State> {
        let id = UUID()
        var captured: AsyncStream<Store.State>.Continuation!
        let stream = AsyncStream<Store.State> { captured = $0 }
        captured.onTermination = { @Sendable [weak self] _ in
            Task { [weak self] in await self?.removeContinuation(id) }
        }
        self.continuations[id] = captured
        return stream
    }

    /// Read the current state (actor-isolated).
    func currentState() -> Store.State {
        self.state
    }

    /// Synchronous, non-actor state read for `ToolbarRenderer`.
    /// Returns a consistent snapshot (either fully before or fully
    /// after the latest `dispatch`).
    nonisolated func snapshot() -> Store.State {
        locked(self.lock) { self.snapshotState }
    }

    // MARK: - Private

    private func publishSnapshot(_ newState: Store.State) {
        locked(self.lock) { self.snapshotState = newState }
    }

    private func removeContinuation(_ id: UUID) {
        self.continuations.removeValue(forKey: id)
    }
}
