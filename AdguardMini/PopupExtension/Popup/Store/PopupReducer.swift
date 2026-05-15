// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  PopupReducer.swift
//  PopupExtension
//

import Foundation
import AML

/// Pure reducer for the popup. All popup business logic lives here —
/// no I/O, no `Date()`/`UUID()` calls, no hidden globals (clocks and
/// identifiers are passed in via state or action payloads). Replaces
/// `PopupView.ViewModel` (~580 LOC) and `PopupStatePreparerImpl`; wired
/// into the runtime via `PopupStore`.
enum PopupReducer {
    // Flat dispatch table; cyclomatic complexity is structural (each branch delegates).
    // swiftlint:disable:next cyclomatic_complexity
    static func reduce(
        state: Store.State,
        action: Store.Action
    ) -> (Store.State, [Store.Effect]) {
        switch action {
        // MARK: External events
        case let .mainAppRunningChanged(running):
            return Self.handleMainAppRunningChanged(state: state, running: running)
        case let .appStateChanged(snapshot):
            return Self.handleAppStateChanged(state: state, snapshot: snapshot)
        case let .themeChanged(theme):
            return (state, [.setAppTheme(theme)])
        case let .logLevelChanged(level):
            return (state, [.setLogLevel(level)])
        case let .tabStatsRefreshed(stats, _):
            var next = state
            next.tabStats = stats
            return (next, [])
        case let .currentTabContextResolved(context):
            var next = state
            next.tabContext = context
            return (next, [])

        // MARK: Toolbar
        case .toolbarValidationRequested:
            return Self.handleToolbarValidationRequested(state: state)
        case .toolbarValidationResolved:
            // Toolbar render reads the snapshot directly; no state change.
            return (state, [])

        // MARK: User actions
        case let .protectionForUrlToggled(enable):
            return Self.handleProtectionForUrlToggled(state: state, enable: enable)
        case .pauseTapped:
            return Self.handlePauseTapped(state: state)
        case .fixItTapped:
            return Self.handleFixItTapped(state: state)
        case .blockElementTapped:
            return Self.handleBlockElementTapped(state: state)
        case .reportIssueTapped:
            return Self.handleReportIssueTapped(state: state)
        case .rateTapped:
            return Self.handleRateTapped(state: state)
        case .settingsTapped:
            return Self.handleSettingsTapped(state: state)
        case .infoButtonTapped:
            return Self.handleInfoButtonTapped(state: state)

        // MARK: Effect completions
        case let .setProtectionStatusCompleted(result):
            return Self.handleSetProtectionStatusCompleted(state: state, result: result)
        case let .setFilteringStatusCompleted(result):
            return Self.handleSetFilteringStatusCompleted(state: state, result: result)
        case let .launchMainAppCompleted(error):
            return Self.handleVoidCompletion(state: state, error: error, errorMap: .launchFailed)
        case let .restartMainAppCompleted(error):
            return Self.handleVoidCompletion(state: state, error: error, errorMap: .restartFailed)
        case let .openSafariSettingsCompleted(error):
            return Self.handleVoidCompletion(state: state, error: error, errorMap: .openSafariSettingsFailed)
        case let .openSettingsCompleted(error):
            return Self.handleVoidCompletion(state: state, error: error, errorMap: .openSettingsFailed)
        case let .reportSiteCompleted(result):
            return Self.handleReportSiteCompleted(state: state, result: result)
        case let .prereqsRefreshed(onboardingCompleted, allExtensionsEnabled):
            return Self.handlePrereqsRefreshed(
                state: state,
                onboardingCompleted: onboardingCompleted,
                allExtensionsEnabled: allExtensionsEnabled
            )

        // MARK: Lifecycle
        case let .popupOpened(openedAt):
            return Self.handlePopupOpened(state: state, openedAt: openedAt)
        case .popupDismissed:
            var next = state
            next.popupSession = .closed
            next.lastError = nil
            return (next, [])
        }
    }
}

// MARK: - Helpers

private extension PopupReducer {
    static func mainOrExtensionsOff(_ state: Store.State) -> Telemetry.Screen {
        state.allExtensionsEnabled ? .main : .extensionsOff
    }

    static func currentLayout(_ state: Store.State) -> Store.PopupLayout {
        LayoutResolver.resolve(
            mainAppRunning: state.mainAppRunning,
            onboardingStatus: state.onboardingStatus,
            protectionEnabled: state.protectionEnabled,
            lastError: state.lastError
        )
    }

    static func pageViewEffects(state: Store.State) -> [Store.Effect] {
        let screen: Telemetry.Screen?
        switch currentLayout(state) {
        case .domain: screen = mainOrExtensionsOff(state)
        case .protectionIsDisabled: screen = .protectionDisabled
        case .somethingWentWrong: screen = .failedEnableProtection
        case .adguardNotLaunched, .onboardingWasntCompleted: screen = nil
        }
        return screen.map { [.sendTelemetry(.pageView($0))] } ?? []
    }

    // MARK: - External events

    static func handleMainAppRunningChanged(
        state: Store.State, running: Bool
    ) -> (Store.State, [Store.Effect]) {
        guard state.mainAppRunning != running else { return (state, []) }
        var next = state
        next.mainAppRunning = running
        if running {
            next.lastResolvedTabUrl = nil
            next.onboardingStatus = .unknown
            return (next, [.refreshPrereqs(markStale: true)])
        }
        return (next, [])
    }

    static func handleAppStateChanged(
        state: Store.State, snapshot: Store.AppStateSnapshot
    ) -> (Store.State, [Store.Effect]) {
        guard snapshot.lastCheckTime > state.lastAppStateTimestamp else {
            return (state, [])
        }
        var next = state
        next.lastAppStateTimestamp = snapshot.lastCheckTime
        next.protectionEnabled = snapshot.isProtectionEnabled
        next.lastResolvedTabUrl = nil

        var effects: [Store.Effect] = []
        if let level = LogLevel(rawValue: Int(snapshot.logLevel)) {
            effects.append(.setLogLevel(level))
        }
        if let theme = Theme(rawValue: Int(snapshot.theme)) {
            effects.append(.setAppTheme(theme))
        }
        return (next, effects)
    }

    // MARK: - Toolbar

    static func handleToolbarValidationRequested(
        state: Store.State
    ) -> (Store.State, [Store.Effect]) {
        let url = state.tabStats.url
        // Empty URL means a secure / system page with no recorded blocks; refreshing would loop.
        if url.isEmpty { return (state, []) }
        // Cache is fresh for this URL — nothing to refresh.
        if state.lastResolvedTabUrl == url { return (state, []) }
        return (state, [.refreshAppState, .refreshPrereqs(markStale: false)])
    }

    // MARK: - User actions

    static func handleProtectionForUrlToggled(
        state: Store.State, enable: Bool
    ) -> (Store.State, [Store.Effect]) {
        guard state.inFlight == nil else { return (state, []) }
        guard let url = state.tabContext.url?.absoluteString, !url.isEmpty else {
            return (state, [])
        }
        var next = state
        next.inFlight = enable ? .enabling : .disabling
        next.lastResolvedTabUrl = nil
        if enable {
            next.pausedUrls.remove(url)
            next.protectionEnabledForCurrentUrl = true
        } else {
            next.pausedUrls.insert(url)
            next.protectionEnabledForCurrentUrl = false
            next.tabStats.adsBlocked = 0
            next.tabStats.trackersBlocked = 0
        }
        let effects: [Store.Effect] = [
            .setFilteringStatusForUrl(url, enable: enable),
            .sendTelemetry(.action(.protectionPopupClick, screen: mainOrExtensionsOff(state)))
        ]
        return (next, effects)
    }

    static func handlePauseTapped(state: Store.State) -> (Store.State, [Store.Effect]) {
        guard state.inFlight == nil else { return (state, []) }
        var next = state
        next.inFlight = .disabling
        next.lastResolvedTabUrl = nil
        return (next, [
            .setProtectionStatus(enable: false),
            .sendTelemetry(.action(.pauseProtectionPopupClick, screen: mainOrExtensionsOff(state)))
        ])
    }

    static func handleFixItTapped(state: Store.State) -> (Store.State, [Store.Effect]) {
        guard state.inFlight == nil else { return (state, []) }
        var next = state
        next.inFlight = .openingSafariSettings
        return (next, [
            .openSafariSettings,
            .sendTelemetry(.action(.fixItPopupClick, screen: mainOrExtensionsOff(state)))
        ])
    }

    static func handleBlockElementTapped(state: Store.State) -> (Store.State, [Store.Effect]) {
        // Instant action — no XPC, no inFlight gate (parity with legacy).
        (state, [
            .dispatchPageScriptMessage(name: "blockElementPing"),
            .dismissPopover,
            .sendTelemetry(.action(.blockElementPopupClick, screen: mainOrExtensionsOff(state)))
        ])
    }

    static func handleReportIssueTapped(state: Store.State) -> (Store.State, [Store.Effect]) {
        guard state.inFlight == nil else { return (state, []) }
        guard let url = state.tabContext.url?.absoluteString, !url.isEmpty else {
            return (state, [])
        }
        var next = state
        next.inFlight = .reporting
        return (next, [
            .reportSite(url: url),
            .sendTelemetry(.action(.reportIssueClick, screen: mainOrExtensionsOff(state)))
        ])
    }

    static func handleRateTapped(state: Store.State) -> (Store.State, [Store.Effect]) {
        // Instant action; sequencing of `dismissPopover` before
        // `openUrlInNewTab` preserved from legacy for parity.
        // swiftlint:disable:next force_unwrapping
        let rateUrl = URL(
            string: "https://link.adtidy.org/forward.html?action=appstore&from=options_screen&app=mac-mini"
        )!
        return (state, [
            .dismissPopover,
            .openUrlInNewTab(rateUrl),
            .sendTelemetry(.action(.rateMiniPopupClick, screen: mainOrExtensionsOff(state)))
        ])
    }

    static func handleSettingsTapped(state: Store.State) -> (Store.State, [Store.Effect]) {
        guard state.inFlight == nil else { return (state, []) }
        var next = state
        next.inFlight = .openingSettings
        let screen: Telemetry.Screen = currentLayout(state) == .protectionIsDisabled
            ? .protectionDisabled
            : mainOrExtensionsOff(state)
        return (next, [
            .openSettings,
            .sendTelemetry(.action(.settingPopupClick, screen: screen))
        ])
    }

    static func handleInfoButtonTapped(state: Store.State) -> (Store.State, [Store.Effect]) {
        guard state.inFlight == nil else { return (state, []) }
        switch currentLayout(state) {
        case .domain:
            return (state, [])
        case .adguardNotLaunched:
            var next = state
            next.inFlight = .launching
            return (next, [.launchMainApp])
        case .protectionIsDisabled:
            var next = state
            next.inFlight = .enabling
            return (next, [.setProtectionStatus(enable: true)])
        case .somethingWentWrong:
            var next = state
            next.inFlight = .restarting
            return (next, [.restartMainApp])
        case .onboardingWasntCompleted:
            var next = state
            next.inFlight = .openingSettings
            return (next, [
                .openSettings,
                .sendTelemetry(.action(.settingPopupClick, screen: mainOrExtensionsOff(state)))
            ])
        }
    }

    // MARK: - Effect completions

    static func handleSetProtectionStatusCompleted(
        state: Store.State, result: Result<EBATimestamp, Store.Error>
    ) -> (Store.State, [Store.Effect]) {
        var next = state
        next.inFlight = nil
        switch result {
        case .success:
            next.lastError = nil
            // Explicit refresh keeps the UI in sync if the app state push is delayed.
            return (next, [.refreshAppState])
        case let .failure(error):
            next.lastError = error
            return (next, [])
        }
    }

    static func handleSetFilteringStatusCompleted(
        state: Store.State, result: Result<EBATimestamp, Store.Error>
    ) -> (Store.State, [Store.Effect]) {
        var next = state
        next.inFlight = nil
        switch result {
        case .success:
            next.lastError = nil
            return (next, [.requestToolbarUpdate])
        case let .failure(error):
            next.lastError = error
            return (next, [])
        }
    }

    static func handleVoidCompletion(
        state: Store.State,
        error: Store.Error?,
        errorMap: Store.Error
    ) -> (Store.State, [Store.Effect]) {
        var next = state
        next.inFlight = nil
        if error != nil {
            next.lastError = errorMap
        } else {
            next.lastError = nil
        }
        return (next, [])
    }

    static func handleReportSiteCompleted(
        state: Store.State, result: Result<URL, Store.Error>
    ) -> (Store.State, [Store.Effect]) {
        var next = state
        next.inFlight = nil
        switch result {
        case let .success(url):
            next.lastError = nil
            return (next, [.openUrlInNewTab(url), .dismissPopover])
        case let .failure(error):
            next.lastError = error
            return (next, [])
        }
    }

    static func handlePrereqsRefreshed(
        state: Store.State,
        onboardingCompleted: Bool,
        allExtensionsEnabled: Bool
    ) -> (Store.State, [Store.Effect]) {
        var next = state
        next.onboardingStatus = onboardingCompleted ? .completed : .notCompleted
        next.allExtensionsEnabled = allExtensionsEnabled
        if let url = state.tabContext.url?.absoluteString, !url.isEmpty {
            next.lastResolvedTabUrl = url
        }
        return (next, [])
    }

    // MARK: - Lifecycle

    static func handlePopupOpened(
        state: Store.State, openedAt: Date
    ) -> (Store.State, [Store.Effect]) {
        switch state.popupSession {
        case .open:
            return (state, [])
        case .closed:
            var next = state
            next.popupSession = .open(openedAt: openedAt)
            return (next, [.notifyWindowOpened] + pageViewEffects(state: state))
        }
    }
}
