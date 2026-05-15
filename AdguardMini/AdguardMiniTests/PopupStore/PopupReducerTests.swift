// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  PopupReducerTests.swift
//  AdguardMiniTests
//

// swiftlint:disable file_length

import XCTest
import AML

// MARK: - Constants

private enum Constants {
    static let anyWindowToken = Store.SafariWindowToken(rawValue: 1)
    static let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
    static let knownTimestamp: EBATimestamp = 100
    static let staleTimestamp: EBATimestamp = 50
    static let freshTimestamp: EBATimestamp = 200
    static let exampleURL = URL(string: "https://example.com")!
    static let siteAURL = URL(string: "https://a.com")!
    static let siteBURL = URL(string: "https://b.com")!
}

final class PopupReducerTests: XCTestCase {
    // MARK: Helpers

    /// Convenience constructor: only the fields touched by the test are
    /// passed; everything else inherits from `Store.State.initial`.
    private func state(
        mainAppRunning: Bool = true,
        onboardingStatus: Store.OnboardingStatus = .completed,
        protectionEnabled: Bool = true,
        protectionEnabledForCurrentUrl: Bool = true,
        allExtensionsEnabled: Bool = true,
        tabStats: TabStats = TabStats(),
        tabContext: Store.TabContext = .empty,
        pausedUrls: Set<String> = [],
        lastResolvedTabUrl: String? = nil,
        inFlight: Store.InFlightAction? = nil,
        lastError: Store.Error? = nil,
        lastAppStateTimestamp: EBATimestamp = .zero,
        popupSession: Store.Session = .closed
    ) -> Store.State {
        Store.State(
            mainAppRunning: mainAppRunning,
            onboardingStatus: onboardingStatus,
            protectionEnabled: protectionEnabled,
            protectionEnabledForCurrentUrl: protectionEnabledForCurrentUrl,
            allExtensionsEnabled: allExtensionsEnabled,
            tabStats: tabStats,
            tabContext: tabContext,
            pausedUrls: pausedUrls,
            lastResolvedTabUrl: lastResolvedTabUrl,
            inFlight: inFlight,
            lastError: lastError,
            lastAppStateTimestamp: lastAppStateTimestamp,
            popupSession: popupSession
        )
    }

    // MARK: Smoke

    func testThemeChangedEmitsSetAppThemeEffect() {
        let initial = self.state()
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .themeChanged(.system)
        )
        XCTAssertEqual(next, initial)
        XCTAssertEqual(effects, [.setAppTheme(.system)])
    }

    func testLogLevelChangedEmitsSetLogLevelEffect() {
        let initial = self.state()
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .logLevelChanged(.debug)
        )
        XCTAssertEqual(next, initial)
        XCTAssertEqual(effects, [.setLogLevel(.debug)])
    }

    func testTabStatsRefreshedReplacesStatsAndEmitsNoEffects() {
        var stats = TabStats()
        stats.adsBlocked = 7
        stats.url = Constants.siteAURL.absoluteString
        let initial = self.state()
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .tabStatsRefreshed(stats, window: Constants.anyWindowToken)
        )
        XCTAssertEqual(next.tabStats, stats)
        XCTAssertTrue(effects.isEmpty)
    }

    func testCurrentTabContextResolvedReplacesContext() {
        let url = Constants.siteAURL
        let context = Store.TabContext(
            windowToken: nil, url: url, domain: url.host!, isSystemPage: false
        )
        let initial = self.state()
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .currentTabContextResolved(context)
        )
        XCTAssertEqual(next.tabContext, context)
        XCTAssertTrue(effects.isEmpty)
    }

    func testToolbarValidationResolvedDoesNotMutateState() {
        let initial = self.state()
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .toolbarValidationResolved(
                window: Constants.anyWindowToken,
                isOn: true,
                badgeText: ""
            )
        )
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: protectionForUrlToggled(false)

    func testProtectionForUrlToggledOffEmitsExpectedStateAndEffects() {
        let url = Constants.exampleURL
        var stats = TabStats()
        stats.adsBlocked = 5
        stats.trackersBlocked = 2
        stats.url = url.absoluteString

        let initial = self.state(
            tabStats: stats,
            tabContext: Store.TabContext(
                windowToken: nil, url: url, domain: url.host!, isSystemPage: false
            ),
            lastResolvedTabUrl: url.absoluteString
        )

        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .protectionForUrlToggled(false)
        )

        XCTAssertEqual(next.inFlight, .disabling)
        XCTAssertTrue(next.pausedUrls.contains(url.absoluteString))
        XCTAssertEqual(next.tabStats.adsBlocked, 0)
        XCTAssertEqual(next.tabStats.trackersBlocked, 0)
        XCTAssertNil(next.lastResolvedTabUrl)
        XCTAssertFalse(next.protectionEnabledForCurrentUrl)
        XCTAssertEqual(
            effects,
            [
                .setFilteringStatusForUrl(url.absoluteString, enable: false),
                .sendTelemetry(.action(.protectionPopupClick, screen: .main))
            ]
        )
    }

    func testProtectionForUrlToggledOnRemovesFromPausedUrls() {
        let url = Constants.exampleURL
        let initial = self.state(
            tabContext: Store.TabContext(
                windowToken: nil, url: url, domain: url.host!, isSystemPage: false
            ),
            pausedUrls: [url.absoluteString],
            lastResolvedTabUrl: url.absoluteString
        )
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .protectionForUrlToggled(true)
        )
        XCTAssertEqual(next.inFlight, .enabling)
        XCTAssertFalse(next.pausedUrls.contains(url.absoluteString))
        XCTAssertTrue(next.protectionEnabledForCurrentUrl)
        XCTAssertNil(next.lastResolvedTabUrl)
        XCTAssertEqual(
            effects,
            [
                .setFilteringStatusForUrl(url.absoluteString, enable: true),
                .sendTelemetry(.action(.protectionPopupClick, screen: .main))
            ]
        )
    }

    func testProtectionForUrlToggledIgnoredWhenTabContextHasNoUrl() {
        let initial = self.state()
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .protectionForUrlToggled(false)
        )
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: inFlight guard

    func testProtectionForUrlToggledIgnoredWhileTogglingProtection() {
        let url = Constants.exampleURL
        let initial = self.state(
            tabContext: Store.TabContext(
                windowToken: nil, url: url, domain: url.host!, isSystemPage: false
            ),
            inFlight: .enabling
        )

        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .protectionForUrlToggled(false)
        )

        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: User actions — pauseTapped, fixItTapped, etc.

    func testPauseTappedEmitsSetProtectionStatusOff() {
        let initial = self.state()
        let (next, effects) = PopupReducer.reduce(state: initial, action: .pauseTapped)
        XCTAssertEqual(next.inFlight, .disabling)
        XCTAssertNil(next.lastResolvedTabUrl)
        XCTAssertEqual(
            effects,
            [
                .setProtectionStatus(enable: false),
                .sendTelemetry(.action(.pauseProtectionPopupClick, screen: .main))
            ]
        )
    }

    func testPauseTappedIgnoredWhileInFlight() {
        let initial = self.state(inFlight: .disabling)
        let (next, effects) = PopupReducer.reduce(state: initial, action: .pauseTapped)
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    func testFixItTappedEmitsOpenSafariSettings() {
        let initial = self.state()
        let (next, effects) = PopupReducer.reduce(state: initial, action: .fixItTapped)
        XCTAssertEqual(next.inFlight, .openingSafariSettings)
        XCTAssertEqual(
            effects,
            [
                .openSafariSettings,
                .sendTelemetry(.action(.fixItPopupClick, screen: .main))
            ]
        )
    }

    func testBlockElementTappedEmitsScriptDispatchAndDismiss() {
        let initial = self.state(allExtensionsEnabled: false)
        let (next, effects) = PopupReducer.reduce(state: initial, action: .blockElementTapped)
        XCTAssertEqual(next, initial)
        XCTAssertEqual(
            effects,
            [
                .dispatchPageScriptMessage(name: "blockElementPing"),
                .dismissPopover,
                .sendTelemetry(.action(.blockElementPopupClick, screen: .extensionsOff))
            ]
        )
    }

    func testReportIssueTappedEmitsReportSiteEffect() {
        let url = Constants.exampleURL
        let initial = self.state(
            tabContext: Store.TabContext(
                windowToken: nil, url: url, domain: url.host!, isSystemPage: false
            )
        )
        let (next, effects) = PopupReducer.reduce(state: initial, action: .reportIssueTapped)
        XCTAssertEqual(next.inFlight, .reporting)
        XCTAssertEqual(
            effects,
            [
                .reportSite(url: url.absoluteString),
                .sendTelemetry(.action(.reportIssueClick, screen: .main))
            ]
        )
    }

    func testRateTappedEmitsDismissAndOpenUrl() {
        let initial = self.state()
        let (next, effects) = PopupReducer.reduce(state: initial, action: .rateTapped)
        XCTAssertEqual(next, initial)
        XCTAssertEqual(effects.count, 3)
        XCTAssertEqual(effects[0], .dismissPopover)
        if case let .openUrlInNewTab(url) = effects[1] {
            XCTAssertEqual(url.host, "link.adtidy.org")
        } else {
            XCTFail("Expected .openUrlInNewTab as second effect, got \(effects[1])")
        }
        XCTAssertEqual(
            effects[2],
            .sendTelemetry(.action(.rateMiniPopupClick, screen: .main))
        )
    }

    func testSettingsTappedScreenIsProtectionDisabledWhenLayoutMatches() {
        let initial = self.state(protectionEnabled: false) // layout = .protectionIsDisabled
        let (next, effects) = PopupReducer.reduce(state: initial, action: .settingsTapped)
        XCTAssertEqual(next.inFlight, .openingSettings)
        XCTAssertEqual(
            effects,
            [
                .openSettings,
                .sendTelemetry(.action(.settingPopupClick, screen: .protectionDisabled))
            ]
        )
    }

    func testSettingsTappedScreenFallsBackToMain() {
        let initial = self.state()
        let (_, effects) = PopupReducer.reduce(state: initial, action: .settingsTapped)
        XCTAssertEqual(
            effects,
            [
                .openSettings,
                .sendTelemetry(.action(.settingPopupClick, screen: .main))
            ]
        )
    }

    // MARK: infoButtonTapped

    func testInfoButtonTappedOnDomainLayoutDoesNothing() {
        let initial = self.state()
        let (next, effects) = PopupReducer.reduce(state: initial, action: .infoButtonTapped)
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    func testInfoButtonTappedOnAdguardNotLaunchedLaunchesApp() {
        let initial = self.state(mainAppRunning: false)
        let (next, effects) = PopupReducer.reduce(state: initial, action: .infoButtonTapped)
        XCTAssertEqual(next.inFlight, .launching)
        XCTAssertEqual(effects, [.launchMainApp])
    }

    func testInfoButtonTappedOnProtectionDisabledEnablesProtection() {
        let initial = self.state(protectionEnabled: false)
        let (next, effects) = PopupReducer.reduce(state: initial, action: .infoButtonTapped)
        XCTAssertEqual(next.inFlight, .enabling)
        XCTAssertEqual(effects, [.setProtectionStatus(enable: true)])
    }

    func testInfoButtonTappedOnSomethingWentWrongRestartsApp() {
        let initial = self.state(lastError: .launchFailed)
        let (next, effects) = PopupReducer.reduce(state: initial, action: .infoButtonTapped)
        XCTAssertEqual(next.inFlight, .restarting)
        XCTAssertEqual(effects, [.restartMainApp])
    }

    func testInfoButtonTappedOnOnboardingNotCompletedOpensSettings() {
        let initial = self.state(onboardingStatus: .notCompleted)
        let (next, effects) = PopupReducer.reduce(state: initial, action: .infoButtonTapped)
        XCTAssertEqual(next.inFlight, .openingSettings)
        XCTAssertEqual(
            effects,
            [
                .openSettings,
                .sendTelemetry(.action(.settingPopupClick, screen: .main))
            ]
        )
    }

    // MARK: appStateChanged timestamp guard

    func testAppStateChangedIgnoredWhenTimestampIsStale() {
        let initial = self.state(
            protectionEnabled: false,
            lastAppStateTimestamp: Constants.knownTimestamp
        )
        let snapshot = Store.AppStateSnapshot(
            isProtectionEnabled: true,
            lastCheckTime: Constants.staleTimestamp,
            logLevel: Int32(LogLevel.verbose.rawValue),
            theme: Int32(Theme.system.rawValue)
        )
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .appStateChanged(snapshot)
        )
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    func testAppStateChangedAcceptedWhenTimestampIsFresh() {
        let initial = self.state(
            protectionEnabled: false,
            lastResolvedTabUrl: Constants.siteAURL.absoluteString,
            lastAppStateTimestamp: Constants.knownTimestamp
        )
        let snapshot = Store.AppStateSnapshot(
            isProtectionEnabled: true,
            lastCheckTime: Constants.freshTimestamp,
            logLevel: Int32(LogLevel.debug.rawValue),
            theme: Int32(Theme.dark.rawValue)
        )
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .appStateChanged(snapshot)
        )
        XCTAssertTrue(next.protectionEnabled)
        XCTAssertEqual(next.lastAppStateTimestamp, Constants.freshTimestamp)
        XCTAssertNil(next.lastResolvedTabUrl)
        XCTAssertTrue(effects.contains(.setAppTheme(.dark)))
    }

    // MARK: mainAppRunningChanged

    func testMainAppRunningChangedTrueResetsLastResolvedTabUrl() {
        let initial = self.state(
            mainAppRunning: false,
            lastResolvedTabUrl: Constants.siteAURL.absoluteString
        )
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .mainAppRunningChanged(true)
        )
        XCTAssertTrue(next.mainAppRunning)
        XCTAssertNil(next.lastResolvedTabUrl)
        XCTAssertEqual(next.onboardingStatus, .unknown)
        XCTAssertEqual(effects, [.refreshPrereqs(markStale: true)])
    }

    func testMainAppRunningChangedFalseClearsRunningFlag() {
        let initial = self.state(mainAppRunning: true)
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .mainAppRunningChanged(false)
        )
        XCTAssertFalse(next.mainAppRunning)
        XCTAssertTrue(effects.isEmpty)
    }

    func testMainAppRunningChangedNoOpWhenValueIsSame() {
        let initial = self.state(mainAppRunning: true)
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .mainAppRunningChanged(true)
        )
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: Toolbar loop-guard (URL matches cache)

    func testToolbarValidationRequestedNoEffectsWhenUrlMatchesCache() {
        var stats = TabStats()
        stats.url = Constants.siteAURL.absoluteString
        let initial = self.state(
            tabStats: stats,
            lastResolvedTabUrl: Constants.siteAURL.absoluteString
        )
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .toolbarValidationRequested(window: Constants.anyWindowToken)
        )
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: Toolbar loop-guard (empty URL)

    func testToolbarValidationRequestedNoXpcRefreshWhenStatsUrlIsEmpty() {
        var stats = TabStats()
        stats.url = ""
        let initial = self.state(tabStats: stats, lastResolvedTabUrl: nil)
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .toolbarValidationRequested(window: Constants.anyWindowToken)
        )
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    func testToolbarValidationRequestedEmitsRefreshWhenUrlMismatch() {
        var stats = TabStats()
        stats.url = Constants.siteAURL.absoluteString
        let initial = self.state(
            tabStats: stats,
            lastResolvedTabUrl: Constants.siteBURL.absoluteString
        )
        let (_, effects) = PopupReducer.reduce(
            state: initial,
            action: .toolbarValidationRequested(window: Constants.anyWindowToken)
        )
        XCTAssertEqual(
            effects,
            [.refreshAppState, .refreshPrereqs(markStale: false)]
        )
    }

    // MARK: Error routing on .domain

    func testSetProtectionStatusFailureOnDomainLayoutResolvesToSomethingWentWrong() {
        let initial = self.state(inFlight: .enabling) // would-be .domain layout
        let (next, _) = PopupReducer.reduce(
            state: initial,
            action: .setProtectionStatusCompleted(.failure(.protectionToggleFailed(domain: nil)))
        )
        XCTAssertNil(next.inFlight)
        XCTAssertEqual(next.lastError, .protectionToggleFailed(domain: nil))
        XCTAssertEqual(
            LayoutResolver.resolve(
                mainAppRunning: next.mainAppRunning,
                onboardingStatus: next.onboardingStatus,
                protectionEnabled: next.protectionEnabled,
                lastError: next.lastError
            ),
            .somethingWentWrong
        )
    }

    // MARK: Error routing on non-.domain

    func testSetProtectionStatusFailureOnProtectionDisabledLayoutKeepsLayout() {
        let initial = self.state(
            protectionEnabled: false,
            inFlight: .enabling
        )
        let (next, _) = PopupReducer.reduce(
            state: initial,
            action: .setProtectionStatusCompleted(.failure(.protectionToggleFailed(domain: nil)))
        )
        XCTAssertNil(next.inFlight)
        XCTAssertNotNil(next.lastError)
        XCTAssertEqual(
            LayoutResolver.resolve(
                mainAppRunning: next.mainAppRunning,
                onboardingStatus: next.onboardingStatus,
                protectionEnabled: next.protectionEnabled,
                lastError: next.lastError
            ),
            .protectionIsDisabled
        )
    }

    // MARK: completions clear inFlight and last error on success

    func testSetProtectionStatusSuccessClearsInFlightAndError() {
        let initial = self.state(
            inFlight: .enabling,
            lastError: .launchFailed
        )
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .setProtectionStatusCompleted(.success(Constants.knownTimestamp))
        )
        XCTAssertNil(next.inFlight)
        XCTAssertNil(next.lastError)
        XCTAssertEqual(effects, [.refreshAppState])
    }

    func testSetFilteringStatusSuccessRequestsToolbarUpdate() {
        let initial = self.state(inFlight: .disabling)
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .setFilteringStatusCompleted(.success(Constants.knownTimestamp))
        )
        XCTAssertNil(next.inFlight)
        XCTAssertEqual(effects, [.requestToolbarUpdate])
    }

    func testSetFilteringStatusFailureSetsError() {
        let initial = self.state(inFlight: .disabling)
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .setFilteringStatusCompleted(.failure(.filteringStateFetchFailed))
        )
        XCTAssertNil(next.inFlight)
        XCTAssertEqual(next.lastError, .filteringStateFetchFailed)
        XCTAssertTrue(effects.isEmpty)
    }

    func testReportSiteSuccessOpensUrlAndDismisses() {
        let initial = self.state(inFlight: .reporting)
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .reportSiteCompleted(.success(Constants.exampleURL))
        )
        XCTAssertNil(next.inFlight)
        XCTAssertEqual(effects, [.openUrlInNewTab(Constants.exampleURL), .dismissPopover])
    }

    func testReportSiteFailureSetsError() {
        let initial = self.state(inFlight: .reporting)
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .reportSiteCompleted(.failure(.reportFailed))
        )
        XCTAssertNil(next.inFlight)
        XCTAssertEqual(next.lastError, .reportFailed)
        XCTAssertTrue(effects.isEmpty)
    }

    func testLaunchMainAppFailureSetsLaunchError() {
        let initial = self.state(mainAppRunning: false, inFlight: .launching)
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .launchMainAppCompleted(.launchFailed)
        )
        XCTAssertNil(next.inFlight)
        XCTAssertEqual(next.lastError, .launchFailed)
        XCTAssertTrue(effects.isEmpty)
    }

    func testLaunchMainAppSuccessClearsLastError() {
        let initial = self.state(inFlight: .launching, lastError: .launchFailed)
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .launchMainAppCompleted(nil)
        )
        XCTAssertNil(next.inFlight)
        XCTAssertNil(next.lastError)
        XCTAssertTrue(effects.isEmpty)
    }

    func testRestartMainAppFailureSetsRestartError() {
        let initial = self.state(inFlight: .restarting)
        let (next, _) = PopupReducer.reduce(
            state: initial,
            action: .restartMainAppCompleted(.restartFailed)
        )
        XCTAssertEqual(next.lastError, .restartFailed)
    }

    func testOpenSafariSettingsFailureSetsOpenSafariSettingsError() {
        let initial = self.state(inFlight: .openingSafariSettings)
        let (next, _) = PopupReducer.reduce(
            state: initial,
            action: .openSafariSettingsCompleted(.openSafariSettingsFailed)
        )
        XCTAssertEqual(next.lastError, .openSafariSettingsFailed)
    }

    func testOpenSettingsFailureSetsOpenSettingsError() {
        let initial = self.state(inFlight: .openingSettings)
        let (next, _) = PopupReducer.reduce(
            state: initial,
            action: .openSettingsCompleted(.openSettingsFailed)
        )
        XCTAssertEqual(next.lastError, .openSettingsFailed)
    }

    // MARK: prereqsRefreshed updates lastResolvedTabUrl

    func testPrereqsRefreshedSetsLastResolvedTabUrlFromContext() {
        let url = Constants.siteAURL
        let initial = self.state(
            tabContext: Store.TabContext(
                windowToken: nil, url: url, domain: url.host!, isSystemPage: false
            ),
            lastResolvedTabUrl: nil
        )
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .prereqsRefreshed(onboardingCompleted: true, allExtensionsEnabled: false)
        )
        XCTAssertEqual(next.onboardingStatus, .completed)
        XCTAssertFalse(next.allExtensionsEnabled)
        XCTAssertEqual(next.lastResolvedTabUrl, url.absoluteString)
        XCTAssertTrue(effects.isEmpty)
    }

    func testPrereqsRefreshedDoesNotSetLastResolvedTabUrlWhenNoContext() {
        let initial = self.state()
        let (next, _) = PopupReducer.reduce(
            state: initial,
            action: .prereqsRefreshed(onboardingCompleted: false, allExtensionsEnabled: true)
        )
        XCTAssertEqual(next.onboardingStatus, .notCompleted)
        XCTAssertNil(next.lastResolvedTabUrl)
    }

    // MARK: pageView session invariant

    func testPopupOpenedFromClosedEmitsPageViewAndOpensSession() {
        let initial = self.state() // .domain layout, .closed session
        let openedAt = Constants.referenceDate
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .popupOpened(openedAt: openedAt)
        )
        XCTAssertEqual(
            next.popupSession,
            .open(openedAt: openedAt)
        )
        XCTAssertEqual(effects, [.notifyWindowOpened, .sendTelemetry(.pageView(.main))])
    }

    func testPopupOpenedSecondCallWithoutDismissDoesNotResendPageView() {
        let openedAt = Constants.referenceDate
        let initial = self.state(popupSession: .open(openedAt: openedAt))
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .popupOpened(openedAt: openedAt.addingTimeInterval(1))
        )
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    func testPopupOpenedOnNonTelemetryLayoutEmitsNoEffects() {
        let openedAt = Constants.referenceDate
        let initial = self.state(mainAppRunning: false) // .adguardNotLaunched
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .popupOpened(openedAt: openedAt)
        )
        XCTAssertEqual(
            next.popupSession,
            .open(openedAt: openedAt)
        )
        XCTAssertEqual(effects, [.notifyWindowOpened])
    }

    func testPopupDismissedClosesSessionAndClearsError() {
        let openedAt = Constants.referenceDate
        let initial = self.state(
            lastError: .launchFailed,
            popupSession: .open(openedAt: openedAt)
        )
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .popupDismissed
        )
        XCTAssertEqual(next.popupSession, .closed)
        XCTAssertNil(next.lastError)
        XCTAssertTrue(effects.isEmpty)
    }

    func testPopupDismissedOnAlreadyClosedSessionStillClearsError() {
        let initial = self.state(
            lastError: .launchFailed,
            popupSession: .closed
        )
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .popupDismissed
        )
        XCTAssertEqual(next.popupSession, .closed)
        XCTAssertNil(next.lastError)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: inFlight guards — non-toggle user actions

    func testFixItTappedIgnoredWhileInFlight() {
        let initial = self.state(inFlight: .openingSafariSettings)
        let (next, effects) = PopupReducer.reduce(state: initial, action: .fixItTapped)
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    func testReportIssueTappedIgnoredWhileInFlight() {
        let url = Constants.exampleURL
        let initial = self.state(
            tabContext: Store.TabContext(
                windowToken: nil, url: url, domain: url.host!, isSystemPage: false
            ),
            inFlight: .reporting
        )
        let (next, effects) = PopupReducer.reduce(state: initial, action: .reportIssueTapped)
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    func testReportIssueTappedIgnoredWhenTabContextHasNoUrl() {
        let initial = self.state()
        let (next, effects) = PopupReducer.reduce(state: initial, action: .reportIssueTapped)
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    func testSettingsTappedIgnoredWhileInFlight() {
        let initial = self.state(inFlight: .openingSettings)
        let (next, effects) = PopupReducer.reduce(state: initial, action: .settingsTapped)
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    func testInfoButtonTappedIgnoredWhileInFlight() {
        let initial = self.state(mainAppRunning: false, inFlight: .launching)
        let (next, effects) = PopupReducer.reduce(state: initial, action: .infoButtonTapped)
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: Telemetry screen — `.extensionsOff` branch of `mainOrExtensionsOff`

    func testProtectionForUrlToggledTelemetryUsesExtensionsOffWhenAllExtensionsDisabled() {
        let url = Constants.exampleURL
        let initial = self.state(
            allExtensionsEnabled: false,
            tabContext: Store.TabContext(
                windowToken: nil, url: url, domain: url.host!, isSystemPage: false
            )
        )
        let (_, effects) = PopupReducer.reduce(
            state: initial,
            action: .protectionForUrlToggled(false)
        )
        XCTAssertEqual(
            effects,
            [
                .setFilteringStatusForUrl(url.absoluteString, enable: false),
                .sendTelemetry(.action(.protectionPopupClick, screen: .extensionsOff))
            ]
        )
    }

    func testPauseTappedTelemetryUsesExtensionsOffScreen() {
        let initial = self.state(allExtensionsEnabled: false)
        let (_, effects) = PopupReducer.reduce(state: initial, action: .pauseTapped)
        XCTAssertEqual(
            effects,
            [
                .setProtectionStatus(enable: false),
                .sendTelemetry(.action(.pauseProtectionPopupClick, screen: .extensionsOff))
            ]
        )
    }

    func testBlockElementTappedTelemetryUsesMainScreenWhenAllExtensionsEnabled() {
        let initial = self.state() // allExtensionsEnabled defaults to true
        let (_, effects) = PopupReducer.reduce(state: initial, action: .blockElementTapped)
        XCTAssertEqual(
            effects,
            [
                .dispatchPageScriptMessage(name: "blockElementPing"),
                .dismissPopover,
                .sendTelemetry(.action(.blockElementPopupClick, screen: .main))
            ]
        )
    }

    // MARK: pageView screen mapping

    func testPopupOpenedOnProtectionDisabledLayoutEmitsProtectionDisabledPageView() {
        let openedAt = Constants.referenceDate
        let initial = self.state(protectionEnabled: false)
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .popupOpened(openedAt: openedAt)
        )
        XCTAssertEqual(
            next.popupSession,
            .open(openedAt: openedAt)
        )
        XCTAssertEqual(effects, [.notifyWindowOpened, .sendTelemetry(.pageView(.protectionDisabled))])
    }

    func testPopupOpenedOnSomethingWentWrongLayoutEmitsFailedEnableProtectionPageView() {
        let openedAt = Constants.referenceDate
        let initial = self.state(lastError: .launchFailed) // .domain + error => .somethingWentWrong
        let (_, effects) = PopupReducer.reduce(
            state: initial,
            action: .popupOpened(openedAt: openedAt)
        )
        XCTAssertEqual(effects, [.notifyWindowOpened, .sendTelemetry(.pageView(.failedEnableProtection))])
    }

    func testPopupOpenedOnDomainWithExtensionsOffEmitsExtensionsOffPageView() {
        let openedAt = Constants.referenceDate
        let initial = self.state(allExtensionsEnabled: false)
        let (_, effects) = PopupReducer.reduce(
            state: initial,
            action: .popupOpened(openedAt: openedAt)
        )
        XCTAssertEqual(effects, [.notifyWindowOpened, .sendTelemetry(.pageView(.extensionsOff))])
    }

    func testPopupOpenedOnOnboardingWasntCompletedEmitsNoTelemetry() {
        let openedAt = Constants.referenceDate
        let initial = self.state(onboardingStatus: .notCompleted)
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .popupOpened(openedAt: openedAt)
        )
        XCTAssertEqual(
            next.popupSession,
            .open(openedAt: openedAt)
        )
        XCTAssertEqual(effects, [.notifyWindowOpened])
    }

    // MARK: appStateChanged — boundary and invalid-rawValue cases

    func testAppStateChangedIgnoredWhenTimestampIsEqual() {
        // Guard is strict `>`, so equal timestamp must be ignored.
        let initial = self.state(
            protectionEnabled: false,
            lastAppStateTimestamp: Constants.knownTimestamp
        )
        let snapshot = Store.AppStateSnapshot(
            isProtectionEnabled: true,
            lastCheckTime: Constants.knownTimestamp,
            logLevel: Int32(LogLevel.debug.rawValue),
            theme: Int32(Theme.dark.rawValue)
        )
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .appStateChanged(snapshot)
        )
        XCTAssertEqual(next, initial)
        XCTAssertTrue(effects.isEmpty)
    }

    func testAppStateChangedIgnoresInvalidLogLevelAndTheme() {
        let initial = self.state(lastAppStateTimestamp: 0)
        let snapshot = Store.AppStateSnapshot(
            isProtectionEnabled: true,
            lastCheckTime: 1,
            logLevel: 99, // out of range for AML.LogLevel
            theme: 99     // out of range for Theme
        )
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .appStateChanged(snapshot)
        )
        XCTAssertEqual(next.lastAppStateTimestamp, 1)
        XCTAssertTrue(next.protectionEnabled)
        XCTAssertTrue(effects.isEmpty)
    }

    func testAppStateChangedEmitsLogLevelBeforeTheme() {
        // Lock in the contractual order. Log level must be set first,
        // Before the theme switch, which can trigger a UI repaint.
        let initial = self.state(lastAppStateTimestamp: 0)
        let snapshot = Store.AppStateSnapshot(
            isProtectionEnabled: true,
            lastCheckTime: 1,
            logLevel: Int32(LogLevel.debug.rawValue),
            theme: Int32(Theme.dark.rawValue)
        )
        let (_, effects) = PopupReducer.reduce(
            state: initial,
            action: .appStateChanged(snapshot)
        )
        XCTAssertEqual(effects, [.setLogLevel(.debug), .setAppTheme(.dark)])
    }

    // MARK: setFilteringStatus success clears prior error

    func testSetFilteringStatusSuccessClearsLastError() {
        let initial = self.state(inFlight: .disabling, lastError: .filteringStateFetchFailed)
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .setFilteringStatusCompleted(.success(Constants.knownTimestamp))
        )
        XCTAssertNil(next.inFlight)
        XCTAssertNil(next.lastError)
        XCTAssertEqual(effects, [.requestToolbarUpdate])
    }

    // MARK: mainAppRunningChanged — true->false preserves cache

    func testMainAppRunningChangedTrueToFalseDoesNotResetCacheOrOnboarding() {
        let initial = self.state(
            mainAppRunning: true,
            onboardingStatus: .completed,
            lastResolvedTabUrl: Constants.siteAURL.absoluteString
        )
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .mainAppRunningChanged(false)
        )
        XCTAssertFalse(next.mainAppRunning)
        XCTAssertEqual(next.onboardingStatus, .completed)
        XCTAssertEqual(next.lastResolvedTabUrl, Constants.siteAURL.absoluteString)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: toolbarValidationRequested — refresh with nil cache

    func testToolbarValidationRequestedEmitsRefreshWhenCacheIsNil() {
        var stats = TabStats()
        stats.url = Constants.siteAURL.absoluteString
        let initial = self.state(tabStats: stats, lastResolvedTabUrl: nil)
        let (next, effects) = PopupReducer.reduce(
            state: initial,
            action: .toolbarValidationRequested(window: Constants.anyWindowToken)
        )
        XCTAssertEqual(next, initial)
        XCTAssertEqual(
            effects,
            [.refreshAppState, .refreshPrereqs(markStale: false)]
        )
    }
}
