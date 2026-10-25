import { LightningElement, api } from 'lwc';

const VARIANT_CLASS = {
    error: 'slds-notify slds-notify_alert slds-alert_error slds-m-bottom_small',
    warning: 'slds-notify slds-notify_alert slds-alert_warning slds-m-bottom_small',
    info: 'slds-notify slds-notify_alert slds-m-bottom_small'
};

/**
 * Reusable alert banner that renders nothing when the messages array is empty.
 *
 * @example
 * <c-bill-split-alert variant="error" messages={errorList}></c-bill-split-alert>
 */
export default class BillSplitAlert extends LightningElement {
    /** @type {'error'|'warning'|'info'} */
    @api variant = 'info';

    /** @type {string[]} */
    @api messages = [];

    get hasMessages() {
        return Array.isArray(this.messages) && this.messages.length > 0;
    }

    get isSingleMessage() {
        return this.messages.length === 1;
    }

    get firstMessage() {
        return this.messages[0];
    }

    get containerClass() {
        return VARIANT_CLASS[this.variant] || VARIANT_CLASS.info;
    }
}