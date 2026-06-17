// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  Throttler.swift
//  AdguardMini
//

import Foundation

/// A generic, reusable rate limiter that fires a side effect on the leading
/// edge of a burst and at most once per window on the trailing edge.
///
/// Implemented as an `actor`, so all access to its mutable state is free of
/// data races even when `schedule()` is called concurrently from arbitrary
/// threads. The throttler owns a single in-flight window task at a time.
///
/// Under sustained pressure the window length doubles each cycle up to
/// `maxDelay`, then resets to `baseDelay` once the burst ends.
final actor Throttler {
    // MARK: Configuration

    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let fire: @Sendable () -> Void
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    // MARK: Mutable state

    /// Whether a throttle window is currently open.
    private var isWindowOpen = false

    /// Whether at least one event arrived while the window was open.
    private var hasPendingUpdate = false

    /// Current window delay.
    private var currentDelay: TimeInterval

    /// The single in-flight window task, or `nil` when idle.
    private var windowTask: Task<Void, Never>?

    /// Monotonic generation counter. Captured by each window task so a
    /// superseded task (after `cancel()` or a new burst) becomes a no-op
    /// instead of corrupting the current state.
    private var generation: UInt64 = 0

    // MARK: Init

    /// Creates a throttler.
    ///
    /// - Parameters:
    ///   - baseDelay: The initial window length and the value the delay resets
    ///     to once a burst ends.
    ///   - maxDelay: The maximum window length adaptive backoff can reach.
    ///   - sleep: The suspension primitive used between windows. Injected so
    ///     tests can drive the state machine deterministically. Defaults to
    ///     `Task.sleep(seconds:)`.
    ///   - fire: The side effect to rate-limit (for example a toolbar update).
    init(
        baseDelay: TimeInterval,
        maxDelay: TimeInterval,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(seconds: $0) },
        fire: @escaping @Sendable () -> Void
    ) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.currentDelay = baseDelay
        self.sleep = sleep
        self.fire = fire
    }

    // MARK: API

    /// Whether a throttle window is currently open. Exposed so tests can assert
    /// the throttler returns to its idle state.
    var isThrottling: Bool {
        self.isWindowOpen
    }

    /// Schedules a throttled fire. The first call of an idle period fires
    /// immediately (leading edge); calls within the open window are coalesced.
    func schedule() {
        guard !self.isWindowOpen else {
            self.hasPendingUpdate = true
            return
        }

        // Leading edge. Reset the delay defensively so a new burst starts fresh.
        // `baseDelay` applies regardless of how the previous burst happened to end.
        self.generation &+= 1
        let newGeneration = self.generation
        self.isWindowOpen = true
        self.hasPendingUpdate = false
        self.currentDelay = self.baseDelay
        self.fire()

        self.windowTask = Task { [self] in
            await self.runBurstLoop(generation: newGeneration)
        }
    }

    /// Cancels the in-flight window, drops any pending trailing update, and
    /// returns the throttler to a clean idle state. Bumping `generation`
    /// neutralizes the cancelled task's resumption so it cannot reopen or close
    /// a window.
    func cancel() {
        self.generation &+= 1
        self.windowTask?.cancel()
        self.windowTask = nil
        self.isWindowOpen = false
        self.hasPendingUpdate = false
        self.currentDelay = self.baseDelay
    }

    // MARK: Private

    /// Runs successive throttle windows until the burst ends or the task is
    /// cancelled. A single long-lived loop avoids spawning a chain of tasks.
    ///
    /// After every suspension the loop checks `generation`: if a newer burst or
    /// a `cancel()` has bumped it, this task is superseded and exits without
    /// mutating shared state.
    private func runBurstLoop(generation newGeneration: UInt64) async {
        while true {
            do {
                try await self.sleep(self.currentDelay)
            } catch {
                if self.generation == newGeneration {
                    self.isWindowOpen = false
                }
                return
            }

            guard self.generation == newGeneration else { return }

            guard self.hasPendingUpdate else {
                // Burst ended.
                self.isWindowOpen = false
                self.currentDelay = self.baseDelay
                self.windowTask = nil
                return
            }

            // Trailing edge: fire once, then ramp up for the next window.
            self.hasPendingUpdate = false
            self.fire()
            self.currentDelay = min(self.currentDelay * 2, self.maxDelay)
        }
    }
}
