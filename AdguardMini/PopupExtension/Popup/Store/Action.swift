// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  Action.swift
//  PopupExtension
//

import Foundation
@preconcurrency import AML

extension Store {
    /// Single entry point into the reducer. All payloads are `Sendable`
    /// and `Equatable` (`Result<Void, Error>` is avoided; void completions
    /// use `Store.Error?` instead so that the whole enum is `Equatable`
    /// and tests can use `XCTAssertEqual` directly).
    /// No references to UI, AppKit, or Safari API objects.
    enum Action: Sendable, Equatable {
        // MARK: External events

        case mainAppRunningChanged(Bool)
        case appStateChanged(AppStateSnapshot)
        case themeChanged(Theme)
        case logLevelChanged(LogLevel)
        case tabStatsRefreshed(TabStats, window: SafariWindowToken)
        case currentTabContextResolved(TabContext)

        // MARK: Toolbar

        case toolbarValidationRequested(window: SafariWindowToken)
        case toolbarValidationResolved(
            window: SafariWindowToken,
            isOn: Bool,
            badgeText: String
        )

        // MARK: User actions

        case protectionForUrlToggled(Bool)
        case pauseTapped
        case fixItTapped
        case blockElementTapped
        case reportIssueTapped
        case rateTapped
        case settingsTapped
        case infoButtonTapped

        // MARK: Effect completions

        case setProtectionStatusCompleted(Result<EBATimestamp, Store.Error>)
        case setFilteringStatusCompleted(Result<EBATimestamp, Store.Error>)
        case launchMainAppCompleted(Store.Error?)
        case restartMainAppCompleted(Store.Error?)
        case openSafariSettingsCompleted(Store.Error?)
        case openSettingsCompleted(Store.Error?)
        case reportSiteCompleted(Result<URL, Store.Error>)
        case prereqsRefreshed(
            onboardingCompleted: Bool,
            allExtensionsEnabled: Bool
        )

        // MARK: Lifecycle

        /// `openedAt` is supplied by the adapter — the reducer is
        /// pure and does not call `Date()` itself.
        case popupOpened(openedAt: Date)
        case popupDismissed
    }
}
