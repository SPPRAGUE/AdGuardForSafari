// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

//
//  PopupCellButton.swift
//  AGSEDesignSystem
//

import SwiftUI
import ColorPalette

// MARK: - UI constants

private enum Constants {
    static var cornerRadius: CGFloat = 0

    static var backgroundColor: StatefulColor {
        StatefulColor(
            enabledColor: .clear,
            disabledColor: .clear,
            pressedColor: Palette.fillsButtonsSecondaryButtonPressed,
            hoveredColor: Palette.fillsButtonsSecondaryButtonHovered
        )
    }
}

// MARK: - PopupCellButton

struct PopupCellButton: View {
    // MARK: Public properties

    var isEnabled: Bool

    var title: String
    var leftIcon: Image
    var rightIcon: Image?

    var leftIconColor: StatefulColor
    var rightIconColor: StatefulColor?
    var titleColor: StatefulColor = Palette.Text.mainText
    var isMultilineTitle: Bool = false
    var backgroundColor: StatefulColor = Constants.backgroundColor

    var action: () -> Void = {}

    // MARK: UI

    var body: some View {
        SEButton(
            configuration: .init(
                appearance: .init(
                    height: nil,
                    cornerRadius: Constants.cornerRadius,
                    backgroundColor: self.backgroundColor
                ),
                isEnabled: self.isEnabled
            ),
            action: self.action
        ) {
            PopupCell(
                configuration: .primary(
                    content: .init(
                        title: self.title,
                        leftIcon: self.leftIcon,
                        rightIcon: self.rightIcon
                    ),
                    leftIconColor: self.leftIconColor,
                    rightIconColor: self.rightIconColor,
                    titleColor: self.titleColor,
                    isMultilineTitle: self.isMultilineTitle,
                    isEnabled: self.isEnabled
                )
            )
        }
        .disabled(!self.isEnabled)
    }
}

// MARK: - PopupCellButton_Previews

#Preview {
    VStack(spacing: 8) {
        PopupCellButton(
            isEnabled: true,
            title: "Block element",
            leftIcon: SEImage.Popup.target,
            leftIconColor: Palette.Icon.errorIcon,
            backgroundColor: Constants.backgroundColor
        )

        PopupCellButton(
            isEnabled: false,
            title: "Block element",
            leftIcon: SEImage.Popup.target,
            leftIconColor: Palette.Icon.errorIcon,
            backgroundColor: Constants.backgroundColor
        )

        PopupCellButton(
            isEnabled: true,
            title: "Report an issue",
            leftIcon: SEImage.Popup.dislike,
            leftIconColor: Palette.Icon.productTertiaryIcon,
            backgroundColor: Constants.backgroundColor
        )

        PopupCellButton(
            isEnabled: false,
            title: "Report an issue",
            leftIcon: SEImage.Popup.dislike,
            leftIconColor: Palette.Icon.productTertiaryIcon,
            backgroundColor: Constants.backgroundColor
        )

        PopupCellButton(
            isEnabled: true,
            title: "Still seeing ads? Learn how to fix this",
            leftIcon: SEImage.Popup.attention,
            rightIcon: SEImage.Popup.arrowRight,
            leftIconColor: Palette.Icon.attentionIcon,
            rightIconColor: Palette.Icon.grayIcon,
            titleColor: Palette.Text.attention,
            isMultilineTitle: true,
            backgroundColor: Constants.backgroundColor
        )

        PopupCellButton(
            isEnabled: false,
            title: "Still seeing ads? Learn how to fix this",
            leftIcon: SEImage.Popup.attention,
            rightIcon: SEImage.Popup.arrowRight,
            leftIconColor: Palette.Icon.attentionIcon,
            rightIconColor: Palette.Icon.grayIcon,
            titleColor: Palette.Text.attention,
            isMultilineTitle: true,
            backgroundColor: Constants.backgroundColor
        )
    }
    .frame(width: 320)
}
