import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class NavToTab extends NavigationMixin(LightningElement) {
    @api labelName = 'Properties';
    @api tabApiName = 'Property__c';
    @api cardTitle;
    @api description;
    @api iconName = 'custom:custom62';
    @api badgeText = 'Quick Link';

    get computedIconName() {
        if (!this.iconName) {
            return 'custom:custom62';
        }
        // Gracefully format motif strings like "Custom62: Building" or "Custom62" to "custom:custom62"
        const customMatch = this.iconName.match(/custom(\d+)/i);
        if (customMatch) {
            return `custom:custom${customMatch[1]}`;
        }
        // If no namespace provided, default to standard
        if (!this.iconName.includes(':')) {
            return `standard:${this.iconName}`;
        }
        return this.iconName;
    }

    get displayTitle() {
        return this.cardTitle || this.labelName || 'Navigation Hub';
    }

    get displayDescription() {
        return (
            this.description ||
            `Navigate directly to ${this.labelName || 'the tab'} to view, create, and manage records.`
        );
    }

    get displayBadge() {
        return this.badgeText || 'Shortcut';
    }

    navigateToTab() {
        if (!this.tabApiName) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: this.tabApiName
            }
        });
    }

    handleTileClick() {
        this.navigateToTab();
    }

    handleButtonClick(event) {
        event.stopPropagation();
        this.navigateToTab();
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.navigateToTab();
        }
    }
}