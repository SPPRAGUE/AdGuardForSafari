// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  LayoutResolver.swift
//  PopupExtension
//

import Foundation

/// Pure function deriving the popup layout from a small set of state flags.
///
/// Precedence (highest first):
///   1. Main app must be running.
///   2. XPC transport must be available.
///   3. Onboarding must not have failed (`.notCompleted`).
///   4. Global protection must be enabled.
///   5. No recorded error in `lastError`.
///   6. Otherwise: `.domain`.
///
/// When `onboardingStatus == .unknown` and the main app is running, the popup
/// renders `.domain` optimistically while the first XPC reply is in flight.
/// This prevents showing `.adguardNotLaunched` during brief XPC initialisation
/// on cold start. The layout will update as soon as `prereqsRefreshed` arrives.
///
/// `lastError` only flips a would-be `.domain` layout to `.somethingWentWrong`.
/// For non-`.domain` layouts the error is surfaced via `popupState = .error`
/// by other code; the layout is preserved.
enum LayoutResolver {
    static func resolve(
        mainAppRunning: Bool,
        onboardingStatus: Store.OnboardingStatus,
        protectionEnabled: Bool,
        lastError: Store.Error?,
        xpcAvailable: Bool = true
    ) -> Store.PopupLayout {
        guard mainAppRunning else { return .adguardNotLaunched }
        guard xpcAvailable else { return .xpcUnavailable }
        switch onboardingStatus {
        case .unknown: return .domain
        case .completed: break
        case .notCompleted: return .onboardingWasntCompleted
        }
        guard protectionEnabled else { return .protectionIsDisabled }
        if lastError != nil { return .somethingWentWrong }
        return .domain
    }
}
