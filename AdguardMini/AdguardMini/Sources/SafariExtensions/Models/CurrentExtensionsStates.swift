// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  CurrentExtensionsStates.swift
//  AdguardMini
//

import Foundation

/// Full available info about all Safari extensions / content blockers.
struct CurrentExtensionsStates {
    let general: CurrentExtensionState
    let privacy: CurrentExtensionState
    let social: CurrentExtensionState
    let security: CurrentExtensionState
    let other: CurrentExtensionState
    let custom: CurrentExtensionState
    let advanced: CurrentExtensionState

    /// All extension statuses as a flat array for iteration.
    var allStatuses: [SafariExtension.Status] {
        [
            general.status, privacy.status, social.status, security.status,
            other.status, custom.status, advanced.status
        ]
    }
}
