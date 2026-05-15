// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  ToolbarRendererTests.swift
//  AdguardMiniTests
//

import XCTest
import SafariServices

// MARK: - Constants

private enum Constants {
    static let exampleUrl = URL(string: "https://example.com")!
    static let otherUrl = URL(string: "https://other.com")!
    static let windowToken = Store.SafariWindowToken(rawValue: 1)
}

// MARK: - ToolbarRendererTests

final class ToolbarRendererTests: XCTestCase {
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

    // MARK: Domain layout, stats (5, 2) -> badge "7"

    func testDomainLayoutReturnsBadgeWithTotal() {
        let url = Constants.exampleUrl
        let sut = self.state(
            tabContext: Store.TabContext(
                windowToken: Constants.windowToken,
                url: url,
                domain: url.host!,
                isSystemPage: false
            )
        )
        let stats = TabStats(
            adsBlocked: 5,
            trackersBlocked: 2,
            url: url.absoluteString
        )
        let badge = ToolbarRendererLogic.computeBadge(
            state: sut, tabStats: stats, showBadge: true
        )
        XCTAssertEqual(badge, "7")
    }

    // MARK: adguardNotLaunched -> empty badge

    func testAdguardNotLaunchedReturnsEmptyBadge() {
        let sut = self.state(mainAppRunning: false)
        let stats = TabStats(adsBlocked: 10, trackersBlocked: 5, url: Constants.exampleUrl.absoluteString)
        let badge = ToolbarRendererLogic.computeBadge(
            state: sut, tabStats: stats, showBadge: true
        )
        XCTAssertEqual(badge, "")
    }

    // MARK: Protection disabled globally -> empty badge

    func testProtectionDisabledReturnsEmptyBadge() {
        let sut = self.state(protectionEnabled: false)
        let stats = TabStats(adsBlocked: 3, trackersBlocked: 1, url: Constants.exampleUrl.absoluteString)
        let badge = ToolbarRendererLogic.computeBadge(
            state: sut, tabStats: stats, showBadge: true
        )
        XCTAssertEqual(badge, "")
    }

    // MARK: Onboarding not completed -> empty badge

    func testOnboardingNotCompletedReturnsEmptyBadge() {
        let sut = self.state(onboardingStatus: .notCompleted)
        let stats = TabStats(adsBlocked: 3, trackersBlocked: 1, url: Constants.exampleUrl.absoluteString)
        let badge = ToolbarRendererLogic.computeBadge(
            state: sut, tabStats: stats, showBadge: true
        )
        XCTAssertEqual(badge, "")
    }

    // MARK: Onboarding unknown -> empty badge

    func testOnboardingUnknownReturnsEmptyBadge() {
        let sut = self.state(onboardingStatus: .unknown)
        let stats = TabStats(adsBlocked: 3, trackersBlocked: 1, url: Constants.exampleUrl.absoluteString)
        let badge = ToolbarRendererLogic.computeBadge(
            state: sut, tabStats: stats, showBadge: true
        )
        XCTAssertEqual(badge, "")
    }

    // MARK: Paused URL -> empty badge

    func testPausedUrlReturnsEmptyBadge() {
        let sut = self.state(pausedUrls: [Constants.exampleUrl.absoluteString])
        let stats = TabStats(adsBlocked: 5, trackersBlocked: 2, url: Constants.exampleUrl.absoluteString)
        let badge = ToolbarRendererLogic.computeBadge(
            state: sut, tabStats: stats, showBadge: true
        )
        XCTAssertEqual(badge, "")
    }

    // MARK: showBadge = false -> empty badge

    func testShowBadgeFalseReturnsEmptyBadge() {
        let url = Constants.exampleUrl
        let sut = self.state(
            tabContext: Store.TabContext(
                windowToken: Constants.windowToken,
                url: url,
                domain: url.host!,
                isSystemPage: false
            )
        )
        let stats = TabStats(adsBlocked: 5, trackersBlocked: 2, url: url.absoluteString)
        let badge = ToolbarRendererLogic.computeBadge(
            state: sut, tabStats: stats, showBadge: false
        )
        XCTAssertEqual(badge, "")
    }

    // MARK: URL mismatch -> protection assumed on -> badge shown

    func testUrlMismatchAssumesProtectionOn() {
        let url = Constants.otherUrl
        let sut = self.state(
            protectionEnabledForCurrentUrl: false,
            tabContext: Store.TabContext(
                windowToken: Constants.windowToken,
                url: url,
                domain: url.host!,
                isSystemPage: false
            )
        )
        let stats = TabStats(adsBlocked: 3, trackersBlocked: 1, url: Constants.exampleUrl.absoluteString)
        let badge = ToolbarRendererLogic.computeBadge(
            state: sut, tabStats: stats, showBadge: true
        )
        XCTAssertEqual(badge, "4")
    }

    // MARK: Empty tabStats.url -> url mismatch -> empty badge

    func testEmptyTabStatsUrlReturnsEmptyBadge() {
        let sut = self.state()
        let stats = TabStats(adsBlocked: 0, trackersBlocked: 0, url: "")
        let badge = ToolbarRendererLogic.computeBadge(
            state: sut, tabStats: stats, showBadge: true
        )
        // Empty URL -> url mismatch -> isProtectedForUrl = true -> isOn = true
        // But badgeText for 0 total is "" (from TabStats.badgeText)
        XCTAssertEqual(badge, "")
    }

    // MARK: Zero stats -> empty badge (badgeText is "")

    func testZeroStatsReturnsEmptyBadge() {
        let url = Constants.exampleUrl
        let sut = self.state(
            tabContext: Store.TabContext(
                windowToken: Constants.windowToken,
                url: url,
                domain: url.host!,
                isSystemPage: false
            )
        )
        let stats = TabStats(adsBlocked: 0, trackersBlocked: 0, url: url.absoluteString)
        let badge = ToolbarRendererLogic.computeBadge(
            state: sut, tabStats: stats, showBadge: true
        )
        XCTAssertEqual(badge, "")
    }

    // MARK: Protection disabled for URL (matching) -> empty badge

    func testProtectionDisabledForUrlReturnsEmptyBadge() {
        let url = Constants.exampleUrl
        let sut = self.state(
            protectionEnabledForCurrentUrl: false,
            tabContext: Store.TabContext(
                windowToken: Constants.windowToken,
                url: url,
                domain: url.host!,
                isSystemPage: false
            )
        )
        let stats = TabStats(adsBlocked: 5, trackersBlocked: 2, url: url.absoluteString)
        let badge = ToolbarRendererLogic.computeBadge(
            state: sut, tabStats: stats, showBadge: true
        )
        XCTAssertEqual(badge, "")
    }

    // MARK: isOn assertions

    func testDomainLayoutIsOnTrue() {
        let url = Constants.exampleUrl
        let sut = self.state(
            tabContext: Store.TabContext(
                windowToken: Constants.windowToken,
                url: url,
                domain: url.host!,
                isSystemPage: false
            )
        )
        let stats = TabStats(adsBlocked: 1, trackersBlocked: 0, url: url.absoluteString)
        let result = ToolbarRendererLogic.compute(
            state: sut, tabStats: stats, showBadge: true
        )
        XCTAssertTrue(result.isOn)
    }

    func testAdguardNotLaunchedIsOnFalse() {
        let sut = self.state(mainAppRunning: false)
        let stats = TabStats(adsBlocked: 1, trackersBlocked: 0, url: Constants.exampleUrl.absoluteString)
        let result = ToolbarRendererLogic.compute(
            state: sut, tabStats: stats, showBadge: true
        )
        XCTAssertFalse(result.isOn)
    }
}
