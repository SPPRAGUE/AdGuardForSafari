// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  RunningAppStream.swift
//  PopupExtension
//

import AppKit
import Foundation

/// Produces an `AsyncStream<Bool>` that emits `true`/`false` whenever
/// the main app starts or stops. Uses KVO on
/// `NSWorkspace.shared.runningApplications`. Observation is cancelled
/// automatically when the stream's consumer stops iterating.
enum RunningAppStream {
    static func stream(bundleId: String) -> AsyncStream<Bool> {
        AsyncStream { continuation in
            var hasEmitted = false
            var lastEmitted = false
            let observation = NSWorkspace.shared.observe(
                \.runningApplications,
                options: [.initial, .new]
            ) { workspace, _ in
                let isRunning = workspace.runningApplications.contains {
                    $0.bundleIdentifier == bundleId
                }
                // Deduplicate
                guard !hasEmitted || isRunning != lastEmitted else { return }
                hasEmitted = true
                lastEmitted = isRunning
                continuation.yield(isRunning)
            }
            continuation.onTermination = { _ in
                observation.invalidate()
            }
        }
    }
}
