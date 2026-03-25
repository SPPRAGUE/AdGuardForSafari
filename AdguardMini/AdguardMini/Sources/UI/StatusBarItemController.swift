// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  StatusBarItemController.swift
//  AdguardMini
//

import Foundation
import AppKit

import AML

// MARK: - StatusBarItemControllerDelegate

protocol StatusBarItemControllerDelegate: AnyObject {
    func handleStatusBarClicked(_ sender: NSStatusBarButton)
}

// MARK: - StatusBarItemController

protocol StatusBarItemController {
    var delegate: StatusBarItemControllerDelegate? { get set }

    func updateTrayIconVisibility(isHidden: Bool) async
    func updateStatusBarIcon() async

    func getTrayIconRect() async -> CGRect

    func openContextMenu(_ sender: NSStatusBarButton)
}

// MARK: - StatusBarItemControllerImpl

final class StatusBarItemControllerImpl: StatusBarItemController {
    /// Status bar element.
    private var statusBarItemView: StatusBarItemView?

    private let storage: SharedSettingsStorage
    private let userSettingsManager: UserSettingsManager

    weak var delegate: StatusBarItemControllerDelegate?

    private var statusBarItemIsHidden: Bool { !self.userSettingsManager.showInMenuBar }

    init(storage: SharedSettingsStorage, userSettingsManager: UserSettingsManager) {
        self.storage = storage
        self.userSettingsManager = userSettingsManager
    }

    @MainActor
    func updateTrayIconVisibility(isHidden: Bool) async {
        LogDebugTrace()
        if isHidden {
            self.statusBarItemView = nil
            return
        }

        await self.updateStatusBarIcon()
    }

    @MainActor
    func updateStatusBarIcon() async {
        LogDebug("Updating status bar icon")

        if self.statusBarItemIsHidden {
            LogDebug("Status bar item is hidden")
            self.statusBarItemView = nil
            return
        }

        if self.statusBarItemView.isNil {
            LogDebug("Recreating status bar item")
            self.statusBarItemView = StatusBarItemView(
                statusItem: NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            )
        }

        self.statusBarItemView?.image = NSImage(
            resource: self.storage.protectionEnabled
            ? .Tray.active
            : .Tray.inactive
        )
        self.statusBarItemView?.setTarget(self)
        self.statusBarItemView?.setAction(#selector(self.handleStatusBarClicked))
        self.statusBarItemView?.listenEvents([.leftMouseUp, .rightMouseUp])
    }

    @MainActor
    func getTrayIconRect() async -> CGRect {
        LogDebugTrace()
        var trayIconRect: CGRect
        if let statusBarItemView = self.statusBarItemView {
            trayIconRect = statusBarItemView.globalRect
        } else {
            LogDebug("No view")
            let screenRect = NSScreen.screens[0].frame
            let size = CGSize(width: NSStatusItem.squareLength, height: NSStatusBar.system.thickness)
            let originX = (screenRect.width - size.width) / 2
            let originY = (screenRect.height - size.height) * 2
            trayIconRect = CGRect(origin: CGPoint(x: originX, y: originY), size: size)
        }
        return trayIconRect
    }

    func openContextMenu(_ sender: NSStatusBarButton) {
        LogDebug("Will open context menu")
        let mainMenu = AppMenu(menuType: .context)
        self.statusBarItemView?.statusItem.menu = mainMenu
        sender.performClick(sender)
        self.statusBarItemView?.statusItem.menu = nil
    }

    @objc
    func handleStatusBarClicked(_ sender: NSStatusBarButton) {
        LogDebug("Handle status bar clicked by \(sender)")
        self.delegate?.handleStatusBarClicked(sender)
    }
}
