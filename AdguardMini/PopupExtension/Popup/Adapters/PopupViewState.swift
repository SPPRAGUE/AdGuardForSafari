// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  PopupViewState.swift
//  PopupExtension
//

import SwiftUI
import AML
import AGSEDesignSystem

/// Thin `@MainActor` adapter between `PopupStore` and SwiftUI.
///
/// Subscribes to the store via `subscribe()` in a single long-lived `Task`,
/// updates `@Published` fields 1:1 with the legacy
/// `PopupView.ViewModel` public API. Bidirectional `Binding<Bool>`
/// for the protection switch is converted into
/// `store.dispatch(.protectionForUrlToggled(...))`.
///
/// No `.sink`/`.map`/`CombineLatest` — `@Published` is used solely
/// as an implementation detail of SwiftUI binding.
///
/// No separate tests — this is a thin adapter; behavior is covered
/// indirectly through `PopupStoreTests` and `PopupReducerTests`.
@MainActor
final class PopupViewState: ObservableObject {
    // MARK: - Published properties (1:1 with legacy ViewModel)

    @Published private(set) var domain: String = ""
    @Published private(set) var isSystemPage: Bool = true
    @Published private(set) var isAllExtensionsEnabled: Bool = true
    @Published private(set) var isOnboardingCompleted: Bool = false
    @Published private(set) var popupLayout: PopupView.Layout = .domain
    @Published private(set) var popupState: InfoView.Configuration.State = .base
    @Published var isProtectionEnabledForUrl: Bool = true
    @Published private(set) var adsBlocked: Int = 0
    @Published private(set) var trackersBlocked: Int = 0

    var isBusy: Bool { popupState == .loading }
    var isPauseButtonAvailable: Bool { popupLayout == .domain }

    // MARK: - Private

    private let store: PopupStore
    private var observationTask: Task<Void, Never>?

    /// Guard to prevent the `isProtectionEnabledForUrl` didSet from
    /// dispatching an action when the value is being set by the
    /// state stream (mirroring the legacy `isInValidation` flag).
    private var isUpdatingFromStore = false

    // MARK: - Init

    init(store: PopupStore) {
        self.store = store
        self.startObserving()
    }

    deinit {
        self.observationTask?.cancel()
    }

    // MARK: - UI Actions

    func fixItClicked() {
        self.dispatch(.fixItTapped)
    }

    func blockElementClicked() {
        self.dispatch(.blockElementTapped)
    }

    func reportAnIssueClicked() {
        self.dispatch(.reportIssueTapped)
    }

    func rateAdguardMiniClicked() {
        self.dispatch(.rateTapped)
    }

    func buttonClicked() {
        self.dispatch(.infoButtonTapped)
    }

    func settingsClicked() {
        self.dispatch(.settingsTapped)
    }

    func pauseClicked() {
        self.dispatch(.pauseTapped)
    }

    func sendPageViewForCurrentLayout() {
        self.dispatch(.popupOpened(openedAt: Date()))
    }

    /// Called by SwiftUI when the protection toggle changes.
    /// Converts the binding write into a store dispatch.
    func protectionToggleChanged(_ newValue: Bool) {
        guard !isUpdatingFromStore else { return }
        self.dispatch(.protectionForUrlToggled(newValue))
    }

    // MARK: - Private

    private func startObserving() {
        self.observationTask = Task { [weak self] in
            guard let self else { return }
            for await state in await self.store.subscribe() {
                guard !Task.isCancelled else { return }
                self.applyState(state)
            }
        }
    }

    private func applyState(_ state: Store.State) {
        self.domain = state.tabContext.domain.isEmpty
            ? .localized.base.item_title_secure_page
            : state.tabContext.domain
        self.isSystemPage = state.tabContext.isSystemPage
        self.isAllExtensionsEnabled = state.allExtensionsEnabled

        self.isOnboardingCompleted = state.onboardingStatus == .completed

        self.popupLayout = self.mapLayout(state)
        self.popupState = self.mapPopupState(state)

        self.isUpdatingFromStore = true
        self.isProtectionEnabledForUrl = state.protectionEnabledForCurrentUrl
        self.isUpdatingFromStore = false

        self.adsBlocked = state.tabStats.adsBlocked
        self.trackersBlocked = state.tabStats.trackersBlocked
    }

    private func mapLayout(_ state: Store.State) -> PopupView.Layout {
        let storeLayout = LayoutResolver.resolve(
            mainAppRunning: state.mainAppRunning,
            onboardingStatus: state.onboardingStatus,
            protectionEnabled: state.protectionEnabled,
            lastError: state.lastError
        )
        switch storeLayout {
        case .domain: return .domain
        case .adguardNotLaunched: return .adguardNotLaunched
        case .protectionIsDisabled: return .protectionIsDisabled
        case .somethingWentWrong: return .somethingWentWrong
        case .onboardingWasntCompleted: return .onboardingWasntCompleted
        }
    }

    private func mapPopupState(_ state: Store.State) -> InfoView.Configuration.State {
        // Loading takes priority — matches legacy behavior.
        // Action-in-flight means loading was set before any error occurred.
        if state.inFlight != nil {
            return .loading
        }
        // Error in non-domain layout → .error.
        // Skipped for .somethingWentWrong — its visual layout handles error presentation.
        let layout = self.mapLayout(state)
        if state.lastError != nil && layout != .somethingWentWrong {
            return .error
        }
        return .base
    }

    private func dispatch(_ action: Store.Action) {
        Task {
            await self.store.dispatch(action)
        }
    }
}
