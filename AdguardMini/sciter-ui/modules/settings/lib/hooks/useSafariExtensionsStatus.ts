// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

import { SafariExtensionStatus } from 'Apis/types';

import { useSettingsStore } from './useSettingsStore';

const BROKEN_EXTENSION_STATUSES = [
    SafariExtensionStatus.unknown,
    SafariExtensionStatus.converter_error,
    SafariExtensionStatus.safari_error,
];

/**
 * Returns derived Safari extension health status flags.
 */
export const useSafariExtensionsStatus = () => {
    const { settings } = useSettingsStore();

    const {
        safariExtensionsLoading,
        safariExtensionsStore: { safariExtensions: extensions, allExtensionsEnabled },
    } = settings;

    const extensionsList = [
        extensions.general,
        extensions.privacy,
        extensions.social,
        extensions.security,
        extensions.other,
        extensions.custom,
        extensions.adguardForSafari,
    ];

    const hasExtensionsDisabled = !allExtensionsEnabled && !safariExtensionsLoading;

    const hasExtensionsBroken = extensionsList.some(
        (extension) => BROKEN_EXTENSION_STATUSES.includes(extension?.status),
    );

    const hasRulesLimitExceeded = extensionsList.some(
        (extension) => extension?.status === SafariExtensionStatus.limit_exceeded,
    );

    return {
        hasExtensionsDisabled,
        hasExtensionsBroken,
        hasRulesLimitExceeded,
    };
};
