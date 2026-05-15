// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  State.swift
//  PopupExtension
//

import Foundation

extension Store {
    /// Single source of truth for the popup. Pure value type,
    /// owns no references. Mutated only by the reducer (added in 2-AFK).
    struct State: Equatable {
        var mainAppRunning: Bool
        var onboardingStatus: OnboardingStatus
        var protectionEnabled: Bool
        var protectionEnabledForCurrentUrl: Bool
        var allExtensionsEnabled: Bool

        var tabStats: TabStats
        var tabContext: TabContext

        var pausedUrls: Set<String>

        /// URL for which `prereqsRefreshed` last arrived after the
        /// matching `tabStatsRefreshed`. `nil` ⇒ next
        /// `toolbarValidationRequested` must trigger a full XPC refresh.
        /// Replaces the legacy `stateNeedsFullRefresh: Bool` magic flag.
        var lastResolvedTabUrl: String?

        var inFlight: InFlightAction?
        var lastError: Store.Error?

        var lastAppStateTimestamp: EBATimestamp
        var popupSession: Session

        static let initial = State(
            mainAppRunning: false,
            onboardingStatus: .unknown,
            protectionEnabled: false,
            protectionEnabledForCurrentUrl: true,
            allExtensionsEnabled: true,
            tabStats: TabStats(),
            tabContext: .empty,
            pausedUrls: [],
            lastResolvedTabUrl: nil,
            inFlight: nil,
            lastError: nil,
            lastAppStateTimestamp: .zero,
            popupSession: .closed
        )
    }
}
