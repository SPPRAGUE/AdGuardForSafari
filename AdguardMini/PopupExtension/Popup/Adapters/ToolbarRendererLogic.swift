// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  ToolbarRendererLogic.swift
//  PopupExtension
//

import Foundation

// MARK: - ToolbarRendererLogic

/// Pure computation extracted from `ToolbarRenderer` for testability.
/// `SFSafariToolbarItem` cannot be instantiated in unit tests;
/// this type contains the logic without Safari API or design-system
/// dependencies and is compiled into `AdguardMiniTests` directly.
enum ToolbarRendererLogic {
    struct RenderResult: Equatable {
        let isOn: Bool
        let badgeText: String
    }

    static func compute(
        state: Store.State,
        tabStats: TabStats,
        showBadge: Bool
    ) -> RenderResult {
        let ready = state.mainAppRunning
            && state.onboardingStatus == .completed
            && state.protectionEnabled

        let cachedUrl = state.tabContext.url?.absoluteString ?? ""
        let urlMatches = !tabStats.url.isEmpty && tabStats.url == cachedUrl
        let isProtectedForUrl = !urlMatches || state.protectionEnabledForCurrentUrl

        let isOn = ready && isProtectedForUrl
        let isPaused = state.pausedUrls.contains(tabStats.url)

        let badgeText = isOn && !isPaused && showBadge
            ? tabStats.badgeText
            : ""

        return RenderResult(isOn: isOn, badgeText: badgeText)
    }

    static func computeBadge(
        state: Store.State,
        tabStats: TabStats,
        showBadge: Bool
    ) -> String {
        compute(state: state, tabStats: tabStats, showBadge: showBadge).badgeText
    }
}
