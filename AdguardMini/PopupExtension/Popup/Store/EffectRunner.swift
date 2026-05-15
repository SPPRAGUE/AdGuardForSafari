// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  EffectRunner.swift
//  PopupExtension
//

import Foundation
import SafariServices
import AML

// MARK: - CancellationCategory

/// Groups effects that should cancel a previously running effect of
/// the same category. Effects not listed here run fire-and-forget
/// and are never individually cancelled.
private enum CancellationCategory: Hashable {
    case protectionStatus
    case filteringStatus
    case appStateRefresh
    case prereqsRefresh
    case launch
    case restart
    case safariSettings
    case settings
    case report
}

private extension Store.Effect {
    var cancellationCategory: CancellationCategory? {
        switch self {
        case .setProtectionStatus:      .protectionStatus
        case .setFilteringStatusForUrl: .filteringStatus
        case .refreshAppState:          .appStateRefresh
        case .refreshPrereqs:           .prereqsRefresh
        case .launchMainApp:            .launch
        case .restartMainApp:           .restart
        case .openSafariSettings:       .safariSettings
        case .openSettings:             .settings
        case .reportSite:               .report
        case .openUrlInNewTab,
             .requestToolbarUpdate,
             .dispatchPageScriptMessage,
             .sendTelemetry,
             .setLogLevel,
             .setAppTheme,
             .dismissPopover,
             .notifyWindowOpened:       nil
        }
    }
}

// MARK: - EffectRunner

final class EffectRunner: EffectRunning, @unchecked Sendable {
    // Dependencies — all protocols, injected at init.
    private let safariApi: SafariApiInteractor
    private let mainAppDiscovery: MainAppDiscovery
    private let safariApp: SafariApp
    private let dismissPopover: @Sendable @MainActor () -> Void

    // Cancellation bookkeeping — guarded by AML's UnfairLock.
    private let lock = UnfairLock()
    private var runningTasks: [CancellationCategory: Task<Void, Never>] = [:]

    init(
        safariApi: SafariApiInteractor,
        mainAppDiscovery: MainAppDiscovery,
        safariApp: SafariApp,
        dismissPopover: @escaping @Sendable @MainActor () -> Void
    ) {
        self.safariApi = safariApi
        self.mainAppDiscovery = mainAppDiscovery
        self.safariApp = safariApp
        self.dismissPopover = dismissPopover
    }

    func run(_ effect: Store.Effect) async -> Store.Action? {
        // Fire-and-forget effects (no completion action).
        switch effect {
        case .requestToolbarUpdate:
            self.safariApp.setToolbarItemsNeedUpdate()
            return nil

        case let .dispatchPageScriptMessage(name):
            if let page = await self.safariApp.getActivePage() {
                page.dispatchMessageToScript(withName: name)
            }
            return nil

        case let .sendTelemetry(event):
            await self.sendTelemetry(event)
            return nil

        case let .setLogLevel(level):
            LogConfig.setLogLevelAsyncly(level)
            return nil

        case let .setAppTheme(theme):
            await NSApplication.shared.setTheme(theme)
            return nil

        case .dismissPopover:
            await self.dismissPopover()
            return nil

        case let .openUrlInNewTab(url):
            await self.safariApp.openUrlInNewTab(url)
            return nil

        case .notifyWindowOpened:
            try? await self.safariApi.notifyWindowOpened()
            return nil

        default:
            break
        }

        // Cancellable effects that produce completion actions.
        return await runCancellable(effect)
    }

    func cancelAll() {
        let tasks = locked(self.lock) {
            let captured = Array(self.runningTasks.values)
            self.runningTasks.removeAll()
            return captured
        }
        tasks.forEach { $0.cancel() }
    }

    func registerTask(_ task: Task<Void, Never>, for effect: Store.Effect) {
        guard let category = effect.cancellationCategory else { return }
        let previous = locked(self.lock) {
            let prev = self.runningTasks[category]
            self.runningTasks[category] = task
            return prev
        }
        previous?.cancel()
    }

    // MARK: - Private

    private func runCancellable(_ effect: Store.Effect) async -> Store.Action? {
        let result = await self.execute(effect)

        // If we were cancelled during execution, suppress the action.
        guard !Task.isCancelled else { return nil }

        // Clean up task tracking.
        if let category = effect.cancellationCategory {
            locked(self.lock) {
                // Only remove if it's still the same task slot (not replaced).
                self.runningTasks[category] = nil
            }
        }

        return result
    }

    private func execute(_ effect: Store.Effect) async -> Store.Action? {
        switch effect {
        case let .setProtectionStatus(enable):
            return await self.executeSetProtectionStatus(enable)
        case let .setFilteringStatusForUrl(url, enable):
            return await self.executeSetFilteringStatus(url: url, enable: enable)
        case .refreshAppState:
            return await self.executeRefreshAppState()
        case .refreshPrereqs:
            return await self.executeRefreshPrereqs()
        case .launchMainApp:
            self.mainAppDiscovery.runMainApplication()
            return .launchMainAppCompleted(nil)
        case .restartMainApp:
            return await self.executeRestartMainApp()
        case .openSafariSettings:
            return await self.executeOpenSafariSettings()
        case .openSettings:
            return await self.executeOpenSettings()
        case let .reportSite(url):
            return await self.executeReportSite(url: url)
        case .openUrlInNewTab, .requestToolbarUpdate,
             .dispatchPageScriptMessage, .sendTelemetry,
             .setLogLevel, .setAppTheme, .dismissPopover,
             .notifyWindowOpened:
            return nil
        }
    }

    private func executeSetProtectionStatus(_ enable: Bool) async -> Store.Action {
        do {
            let timestamp = try await self.safariApi.setProtectionStatus(enable)
            return .setProtectionStatusCompleted(.success(timestamp))
        } catch {
            return .setProtectionStatusCompleted(
                .failure(.protectionToggleFailed(domain: nil))
            )
        }
    }

    private func executeSetFilteringStatus(url: String, enable: Bool) async -> Store.Action {
        do {
            let timestamp = try await self.safariApi.setFilteringStatusWithUrl(
                url, isEnabled: enable
            )
            return .setFilteringStatusCompleted(.success(timestamp))
        } catch {
            return .setFilteringStatusCompleted(
                .failure(.filteringStateFetchFailed)
            )
        }
    }

    private func executeRefreshAppState() async -> Store.Action? {
        do {
            let appState = try await self.safariApi.appState()
            return .appStateChanged(Store.AppStateSnapshot(
                isProtectionEnabled: appState.isProtectionEnabled,
                lastCheckTime: appState.lastCheckTime,
                logLevel: appState.logLevel,
                theme: appState.theme
            ))
        } catch {
            return nil
        }
    }

    private func executeRefreshPrereqs() async -> Store.Action? {
        do {
            async let onboarding = self.safariApi.isOnboardingCompleted()
            async let extensions = self.safariApi.isAllExtensionsEnabled()
            return .prereqsRefreshed(
                onboardingCompleted: try await onboarding,
                allExtensionsEnabled: try await extensions
            )
        } catch {
            return nil
        }
    }

    private func executeRestartMainApp() async -> Store.Action {
        do {
            try await self.mainAppDiscovery.restartMainApplication()
            return .restartMainAppCompleted(nil)
        } catch {
            return .restartMainAppCompleted(.restartFailed)
        }
    }

    private func executeOpenSafariSettings() async -> Store.Action {
        do {
            try await self.safariApi.openSafariSettings()
            return .openSafariSettingsCompleted(nil)
        } catch {
            return .openSafariSettingsCompleted(.openSafariSettingsFailed)
        }
    }

    private func executeOpenSettings() async -> Store.Action {
        do {
            try await self.mainAppDiscovery.openSettings()
            return .openSettingsCompleted(nil)
        } catch {
            return .openSettingsCompleted(.openSettingsFailed)
        }
    }

    private func executeReportSite(url: String) async -> Store.Action {
        do {
            let reportUrlString = try await self.safariApi.reportSite(with: url)
            guard let reportUrl = URL(string: reportUrlString) else {
                return .reportSiteCompleted(.failure(.reportFailed))
            }
            return .reportSiteCompleted(.success(reportUrl))
        } catch {
            return .reportSiteCompleted(.failure(.reportFailed))
        }
    }

    private func sendTelemetry(_ event: Telemetry.Event) async {
        do {
            switch event {
            case let .pageView(screen):
                try await self.safariApi.telemetryPageViewEvent(screen)
            case let .action(action, screen):
                try await self.safariApi.telemetryActionEvent(
                    action, screen: screen
                )
            }
        } catch {
            LogDebug("Can't send telemetry event: \(error)")
        }
    }
}
