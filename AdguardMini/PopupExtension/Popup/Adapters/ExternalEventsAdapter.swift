// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  ExternalEventsAdapter.swift
//  PopupExtension
//

import Foundation
import SafariServices
import AML

// MARK: - RunningAppStreaming

/// Abstraction over `RunningAppStream` for testability.
protocol RunningAppStreaming: Sendable {
    func stream() -> AsyncStream<Bool>
}

/// Production implementation — delegates to `RunningAppStream`.
struct LiveRunningAppStream: RunningAppStreaming {
    func stream() -> AsyncStream<Bool> {
        RunningAppStream.stream(bundleId: BuildConfig.AG_APP_ID)
    }
}

// MARK: - ExternalEventsAdapter

/// Single subscription point for external push sources.
/// Converts each event into a `Store.Action` and dispatches
/// it to `PopupStore`. Conforms to `ExtensionSafariApiClientDelegate`
/// to receive XPC pushes from the main app. Also provides on-demand
/// tab stats polling via `refreshTabStats(in:)`.
///
/// Lifecycle: `start()` begins all subscriptions; `stop()` cancels
/// them. Both are idempotent.
final class ExternalEventsAdapter: NSObject, @unchecked Sendable {
    private let store: PopupStore
    private let runningAppStream: RunningAppStreaming
    private let perTabStatsTracker: PerTabStatsTracker

    private let lock = UnfairLock()
    private var runningAppTask: Task<Void, Never>?

    init(
        store: PopupStore,
        perTabStatsTracker: PerTabStatsTracker,
        runningAppStream: RunningAppStreaming = LiveRunningAppStream()
    ) {
        self.store = store
        self.perTabStatsTracker = perTabStatsTracker
        self.runningAppStream = runningAppStream
    }

    // MARK: - Lifecycle

    func start() {
        locked(self.lock) {
            guard runningAppTask == nil else { return }
            let stream = self.runningAppStream.stream()
            self.runningAppTask = Task { [weak self] in
                for await isRunning in stream {
                    guard let self, !Task.isCancelled else { return }
                    await self.store.dispatch(.mainAppRunningChanged(isRunning))
                }
            }
        }
    }

    func stop() {
        let task = locked(self.lock) {
            let current = self.runningAppTask
            self.runningAppTask = nil
            return current
        }
        task?.cancel()
    }

    // MARK: - On-demand polling

    /// Polls tab stats for the active tab in `window` and dispatches
    /// the result to the store. Called by the toolbar validation
    /// entrypoint (`SafariExtensionHandler.validateToolbarItem`).
    func refreshTabStats(in window: SFSafariWindow) async {
        let stats = await self.perTabStatsTracker.getStatsForActiveTab(in: window)
        let token = Store.SafariWindowToken(rawValue: UInt64(UInt(bitPattern: ObjectIdentifier(window))))
        await self.store.dispatch(.tabStatsRefreshed(stats, window: token))
    }
}

// MARK: - ExtensionSafariApiClientDelegate

extension ExternalEventsAdapter: ExtensionSafariApiClientDelegate {
    func appStateChanged(_ appState: EBAAppState) {
        // Read fields immediately — EBAAppState is a reference type
        // (may be mutated after this call returns).
        let snapshot = Store.AppStateSnapshot(
            isProtectionEnabled: appState.isProtectionEnabled,
            lastCheckTime: appState.lastCheckTime,
            logLevel: appState.logLevel,
            theme: appState.theme
        )
        Task {
            await self.store.dispatch(.appStateChanged(snapshot))
        }
    }

    func setLogLevel(_ logLevel: LogLevel) {
        Task {
            await self.store.dispatch(.logLevelChanged(logLevel))
        }
    }

    func setTheme(_ theme: Theme) {
        Task {
            await self.store.dispatch(.themeChanged(theme))
        }
    }
}
