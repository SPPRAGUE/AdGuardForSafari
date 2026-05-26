// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  ToolbarRenderer.swift
//  PopupExtension
//

import SafariServices
import AGSEDesignSystem

/// Synchronous rendering of the Safari toolbar icon and badge from
/// a `Store.State` snapshot. Called by `SafariExtensionHandler
/// .validateToolbarItem` — runs on Safari's thread, no `await`,
/// no XPC.
///
/// After rendering, the caller dispatches
/// `Action.toolbarValidationRequested(window:requestedAt:)` into the store;
/// the reducer decides whether a background XPC refresh is needed.
enum ToolbarRenderer {
    /// Render toolbar item and return the badge text for Safari's
    /// `validationHandler`.
    ///
    /// - Parameters:
    ///   - state: Synchronous snapshot from `PopupStore.snapshot()`.
    ///   - tabStats: Fresh per-tab statistics from `PerTabStatsTracker`.
    ///   - showBadge: Whether the user has enabled badge display
    ///     (`SharedSettingsStorage.showSafariToolbarBadge`).
    ///   - toolbarItem: Safari toolbar item to configure icon on.
    /// - Returns: Badge text string for `validationHandler(true, _)`.
    static func render(
        state: Store.State,
        tabStats: TabStats,
        showBadge: Bool,
        into toolbarItem: SFSafariToolbarItem
    ) -> String {
        let result = ToolbarRendererLogic.compute(
            state: state, tabStats: tabStats, showBadge: showBadge
        )
        toolbarItem.setImage(
            result.isOn ? SEImage.Toolbar.nsToolbarOn : SEImage.Toolbar.nsToolbarOff
        )
        return result.badgeText
    }
}
