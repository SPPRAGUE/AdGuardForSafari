// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  LayoutResolverTests.swift
//  AdguardMiniTests
//

import XCTest

// MARK: - Constants

private enum Constants {
    static let exampleDomain = "example.com"
}

final class LayoutResolverTests: XCTestCase {    // MARK: Helpers

    private func resolve(
        mainAppRunning: Bool = true,
        onboardingStatus: Store.OnboardingStatus = .completed,
        protectionEnabled: Bool = true,
        lastError: Store.Error? = nil
    ) -> Store.PopupLayout {
        LayoutResolver.resolve(
            mainAppRunning: mainAppRunning,
            onboardingStatus: onboardingStatus,
            protectionEnabled: protectionEnabled,
            lastError: lastError
        )
    }

    // MARK: Happy path

    func testHappyPathProducesDomain() {
        XCTAssertEqual(self.resolve(), .domain)
    }

    // MARK: Main app dominance

    func testMainAppNotRunningAlwaysProducesAdguardNotLaunched() {
        // Truth table: 3 remaining flags free, must be .adguardNotLaunched for every combination.
        for status in [Store.OnboardingStatus.unknown, .completed, .notCompleted] {
            for protectionOn in [false, true] {
                XCTAssertEqual(
                    self.resolve(
                        mainAppRunning: false,
                        onboardingStatus: status,
                        protectionEnabled: protectionOn
                    ),
                    .adguardNotLaunched,
                    "mainAppRunning=false must dominate; status=\(status) protectionOn=\(protectionOn)"
                )
            }
        }
    }

    // MARK: Onboarding gating

    func testUnknownOnboardingProducesAdguardNotLaunched() {
        // Until the first XPC reply from main app arrives, treat the popup as
        // "not launched" to suppress a one-frame flash to .domain or
        // .onboardingWasntCompleted on cold start.
        XCTAssertEqual(
            self.resolve(onboardingStatus: .unknown),
            .adguardNotLaunched
        )
    }

    func testNotCompletedOnboardingProducesOnboardingWasntCompleted() {
        XCTAssertEqual(
            self.resolve(onboardingStatus: .notCompleted),
            .onboardingWasntCompleted
        )
    }

    // MARK: Protection gating

    func testProtectionDisabledProducesProtectionIsDisabled() {
        XCTAssertEqual(
            self.resolve(protectionEnabled: false),
            .protectionIsDisabled
        )
    }

    // MARK: Error routing

    func testDomainBranchWithErrorProducesSomethingWentWrong() {
        // When the resolved layout would be .domain and there is a recorded error.
        // Layout flips to .somethingWentWrong.
        XCTAssertEqual(
            self.resolve(lastError: .protectionToggleFailed(domain: Constants.exampleDomain)),
            .somethingWentWrong
        )
    }

    func testNonDomainBranchKeepsLayoutOnError() {
        // For non-.domain branches, error does not change the layout.
        // The error is surfaced via popupState
        // = .error elsewhere; the resolver simply preserves the layout.
        XCTAssertEqual(
            self.resolve(protectionEnabled: false, lastError: .openSettingsFailed),
            .protectionIsDisabled
        )
        XCTAssertEqual(
            self.resolve(onboardingStatus: .notCompleted, lastError: .launchFailed),
            .onboardingWasntCompleted
        )
        XCTAssertEqual(
            self.resolve(mainAppRunning: false, lastError: .launchFailed),
            .adguardNotLaunched
        )
    }

    // MARK: Priority ordering — exhaustive truth table

    /// Lock down the precedence chain so future changes to the resolver
    /// must update this test:
    ///   1. !mainAppRunning             -> .adguardNotLaunched
    ///   2. onboardingStatus == .unknown -> .adguardNotLaunched
    ///   3. onboardingStatus == .notCompleted -> .onboardingWasntCompleted
    ///   4. !protectionEnabled          -> .protectionIsDisabled
    ///   5. lastError != nil            -> .somethingWentWrong
    ///   6. otherwise                   -> .domain
    func testFullTruthTablePrecedence() {
        let allStatuses: [Store.OnboardingStatus] = [.unknown, .completed, .notCompleted]
        for mainAppRunning in [false, true] {
            for onboardingStatus in allStatuses {
                for protectionEnabled in [false, true] {
                    for hasError in [false, true] {
                        let lastError: Store.Error? = hasError ? .appStateFetchFailed : nil
                        let actual = self.resolve(
                            mainAppRunning: mainAppRunning,
                            onboardingStatus: onboardingStatus,
                            protectionEnabled: protectionEnabled,
                            lastError: lastError
                        )
                        let expected: Store.PopupLayout = {
                            if !mainAppRunning { return .adguardNotLaunched }
                            if onboardingStatus == .unknown { return .adguardNotLaunched }
                            if onboardingStatus == .notCompleted { return .onboardingWasntCompleted }
                            if !protectionEnabled { return .protectionIsDisabled }
                            if lastError != nil { return .somethingWentWrong }
                            return .domain
                        }()
                        XCTAssertEqual(
                            actual, expected,
                            "mainAppRunning=\(mainAppRunning) onboardingStatus=\(onboardingStatus) protectionEnabled=\(protectionEnabled) hasError=\(hasError)"
                        )
                    }
                }
            }
        }
    }
}
