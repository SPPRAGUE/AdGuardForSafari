// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  DIContainer.swift
//  PopupExtension
//

import SafariServices
import AML

// MARK: - DIContainer

/// A class containing all the objects needed for the popup
///
/// - Note: Should be inited as soon as possible: it also configures the logger
@MainActor
final class DIContainer {
    // MARK: Singleton

    static let shared: DIContainer = DIContainer()

    // MARK: Public properties

    let safariController: PopupViewController
    let advancedBlockerHandler: AdvancedBlockerHandler

    let safariApiInteractor: SafariApiInteractor
    let sharedSettingsStorage: SharedSettingsStorage = SharedSettingsStorageImpl()
    let mainAppDiscovery: MainAppDiscovery = MainAppDiscoveryImpl()
    let blockingStatsReporter: BlockingStatsReporter
    let perTabStatsTracker: PerTabStatsTracker = PerTabStatsTracker()

    /// Actor-isolated UDF store — singleton for the extension lifetime.
    let popupStore: PopupStore

    /// Adapter bridging external events (NSWorkspace, XPC, tab stats)
    /// into `Store.Action` dispatches. Also conforms to
    /// `ExtensionSafariApiClientDelegate`.
    let externalEventsAdapter: ExternalEventsAdapter

    // MARK: Private properties

    private let safariApp: SafariApp = SafariAppImpl()
    private let effectRunner: EffectRunner
    private let popupViewState: PopupViewState

    private let filtersStorage: FiltersStorage = {
        let fileManager = AMFileManagerImpl()
        let fileStorage = GroupFolderFileServiceImpl(fileManager: fileManager)
        return FiltersStorageImpl(fileStorage: fileStorage)
    }()

    // MARK: Init

    private init() {
        let subsystem = Subsystem.safariPopup
        LogConfig.setupSharedLogger(for: subsystem)
        SharedSentryUtilities.startSentryForPlugin(subsystem: subsystem)

        let safariApi = ExtensionSafariApiClientImpl()
        self.safariApiInteractor = SafariApiInteractorImpl(safariApi: safariApi)

        self.advancedBlockerHandler = AdvancedBlockerHandlerImpl(
            webExtension: WebExtensionDIContainer.shared.webExtension,
            sharedSettingsStorage: self.sharedSettingsStorage
        )

        // Build the UDF component graph. `PopupViewController` is captured
        // Lazily so `EffectRunner` can reference it before it is created.
        var controllerRef: PopupViewController?

        self.effectRunner = EffectRunner(
            safariApi: self.safariApiInteractor,
            mainAppDiscovery: self.mainAppDiscovery,
            safariApp: self.safariApp,
            // Labeled parameter makes the role of the closure explicit.
            // swiftlint:disable:next trailing_closure
            dismissPopover: { @MainActor in
                controllerRef?.dismissPopover()
            }
        )

        self.popupStore = PopupStore(effectRunner: self.effectRunner)

        self.externalEventsAdapter = ExternalEventsAdapter(
            store: self.popupStore
        )
        safariApi.delegate = self.externalEventsAdapter

        self.popupViewState = PopupViewState(store: self.popupStore)
        let mainView = PopupView(viewState: self.popupViewState)
        self.safariController = PopupViewController(
            mainView: mainView,
            viewState: self.popupViewState
        )
        controllerRef = self.safariController

        self.externalEventsAdapter.start()

        let statsStore: StatisticsStore = {
            do {
                return try SharedStatisticsStoreImpl()
            } catch {
                LogError("Failed to initialize SharedStatisticsStore in PopupExtension: \(error)")
                return NoOpStatisticsStore()
            }
        }()
        self.blockingStatsReporter = BlockingStatsReporterImpl(
            statisticsStore: statsStore,
            sharedSettings: self.sharedSettingsStorage
        )
    }
}
