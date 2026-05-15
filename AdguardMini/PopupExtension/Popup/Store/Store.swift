// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  Store.swift
//  PopupExtension
//

import Foundation

// MARK: - Store namespace

/// Namespace for the new UDF popup architecture.
///
/// All types under `Store` are pure value types, `Sendable`, and have no
/// references to UI or Safari API objects.
enum Store {
    // MARK: PopupLayout

    enum PopupLayout: Equatable {
        case domain
        case adguardNotLaunched
        case protectionIsDisabled
        case somethingWentWrong
        case onboardingWasntCompleted
    }

    // MARK: OnboardingStatus

    /// Tri-state replacement for the legacy pair of
    /// `onboardingCompleted: Bool` + `onboardingStateFresh: Bool`.
    /// `.unknown` = first XPC reply from main app has not arrived yet;
    /// the resolver treats it as "not launched" to avoid a one-frame flash
    /// of `.onboardingWasntCompleted` on cold start.
    enum OnboardingStatus: Equatable {
        case unknown
        case completed
        case notCompleted
    }

    // MARK: SafariWindowToken

    /// Opaque identifier for an `SFSafariWindow`. Does not retain
    /// the window. The mapping `SFSafariWindow → SafariWindowToken` lives in
    /// `ExternalEventsAdapter`.
    struct SafariWindowToken: Hashable {
        let rawValue: UInt64
    }

    // MARK: Session

    /// Sum type instead of separate fields with co-dependent validity:
    /// `.closed` carries no payload; `.open` carries everything that only
    /// makes sense while the popup is on screen.
    enum Session: Equatable {
        case closed
        case open(openedAt: Date)
    }

    // MARK: InFlightAction

    enum InFlightAction: Equatable {
        case enabling
        case disabling
        case launching
        case restarting
        case openingSettings
        case openingSafariSettings
        case reporting
    }

    // MARK: Error

    /// Domain errors surfaced to `Store.State.lastError` for UI rendering.
    /// Conforms to `Swift.Error` only because `Result<Success, Failure>`
    /// requires `Failure: Error`; this type still represents a *summary* of
    /// failures rather than a thrown source.
    enum Error: Swift.Error, Equatable {
        case protectionToggleFailed(domain: String?)
        case launchFailed
        case restartFailed
        case openSafariSettingsFailed
        case openSettingsFailed
        case reportFailed
        case appStateFetchFailed
        case filteringStateFetchFailed
    }

    // MARK: AppStateSnapshot

    /// Projection of `EBAAppState` for use inside actions.
    /// Built by `ExternalEventsAdapter` from the Obj-C class.
    struct AppStateSnapshot: Equatable {
        let isProtectionEnabled: Bool
        let lastCheckTime: EBATimestamp
        let logLevel: Int32
        let theme: Int32
    }

    // MARK: TabContext

    struct TabContext: Equatable {
        var windowToken: SafariWindowToken?
        var url: URL?
        var domain: String
        var isSystemPage: Bool

        static let empty = TabContext(
            windowToken: nil,
            url: nil,
            domain: "",
            isSystemPage: true
        )
    }
}
