// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  LayoutResolver.swift
//  PopupExtension
//

import Foundation

/// Pure function deriving the popup layout from a small set of state flags.
/// Replaces the `CombineLatest4` pipeline in the legacy `PopupView.ViewModel`.
///
/// Precedence (highest first):
///   1. Main app must be running.
///   2. Onboarding status must not be `.unknown` (avoids a one-frame flash
///      to `.domain`/`.onboardingWasntCompleted` on cold start while the XPC
///      reply is in flight).
///   3. Onboarding must be completed.
///   4. Global protection must be enabled.
///   5. No recorded error in `lastError`.
///   6. Otherwise: `.domain`.
///
/// `lastError` only flips a would-be `.domain` layout to `.somethingWentWrong`.
/// For non-`.domain` layouts the error is surfaced via `popupState = .error`
/// by other code; the layout is preserved.
enum LayoutResolver {
    static func resolve(
        mainAppRunning: Bool,
        onboardingStatus: Store.OnboardingStatus,
        protectionEnabled: Bool,
        lastError: Store.Error?
    ) -> Store.PopupLayout {
        guard mainAppRunning else { return .adguardNotLaunched }
        switch onboardingStatus {
        case .unknown: return .adguardNotLaunched
        case .notCompleted: return .onboardingWasntCompleted
        case .completed: break
        }
        guard protectionEnabled else { return .protectionIsDisabled }
        if lastError != nil { return .somethingWentWrong }
        return .domain
    }
}
