// SPDX-FileCopyrightText: AdGuard Software Limited
//
// SPDX-License-Identifier: GPL-3.0-or-later

import { makeAutoObservable } from 'mobx';

import { SafariExtensions, SafariExtension, SafariExtensionStatus, SafariExtensionType } from 'Apis/types';

import type { SafariExtensionUpdate } from 'Apis/types';

/**
 * Store for managing Safari extensions state.
 * Provides computed properties and actions for Safari extension management.
 */
export class SafariExtensionsStore {
    public safariExtensions = new SafariExtensions();

    /**
     * Ctor
     */
    constructor() {
        makeAutoObservable(this);
    }

    /**
     * Get list of all Safari extensions by dynamically iterating over protobuf getters.
     * Uses property descriptors to avoid manual enumeration.
     * Computed getter for MobX caching.
     */
    private get extensionsList(): SafariExtension[] {
        const descriptors = Object.getOwnPropertyDescriptors(
            Object.getPrototypeOf(this.safariExtensions),
        );

        return Object.entries(descriptors)
            .filter(([, desc]) => typeof desc.get === 'function')
            .map(([key]) => this.safariExtensions[key as keyof SafariExtensions])
            .filter((value): value is SafariExtension => value instanceof SafariExtension);
    }

    /**
     * Whether all safari extensions are enabled.
     * Computed from individual isConsideredEnabled flags set by Swift.
     */
    public get allExtensionsEnabled(): boolean {
        return this.extensionsList.every((ext) => ext.isConsideredEnabled);
    }

    /**
     * Get count of safari extensions.
     */
    public get safariExtensionsCount(): number {
        return this.extensionsList.length;
    }

    /**
     * Get count of enabled safari extensions.
     * Uses isConsideredEnabled flag computed by Swift.
     */
    public get enabledSafariExtensionsCount(): number {
        return this.extensionsList.filter((ext) => ext.isConsideredEnabled).length;
    }

    /**
     * Getter for safari extensions with loading status.
     */
    public get safariExtensionsLoading(): boolean {
        return this.extensionsList.some((ext) => ext.status === SafariExtensionStatus.loading);
    }

    /**
     * Set safari protection status.
     */
    public setSafariExtensions(data: SafariExtensions): void {
        this.safariExtensions = data;
    }

    /**
     * Updates safari extension.
     */
    public updateSafariExtension(data: SafariExtensionUpdate): void {
        const newState = new SafariExtensions();
        newState.adguardForSafari = this.safariExtensions.adguardForSafari;
        newState.custom = this.safariExtensions.custom;
        newState.general = this.safariExtensions.general;
        newState.other = this.safariExtensions.other;
        newState.privacy = this.safariExtensions.privacy;
        newState.security = this.safariExtensions.security;
        newState.social = this.safariExtensions.social;

        switch (data.type) {
            case SafariExtensionType.adguard_for_safari:
                newState.adguardForSafari = data.state;
                break;
            case SafariExtensionType.custom:
                newState.custom = data.state;
                break;
            case SafariExtensionType.general:
                newState.general = data.state;
                break;
            case SafariExtensionType.other:
                newState.other = data.state;
                break;
            case SafariExtensionType.privacy:
                newState.privacy = data.state;
                break;
            case SafariExtensionType.security:
                newState.security = data.state;
                break;
            case SafariExtensionType.social:
                newState.social = data.state;
                break;
        }

        this.setSafariExtensions(newState);
    }
}
