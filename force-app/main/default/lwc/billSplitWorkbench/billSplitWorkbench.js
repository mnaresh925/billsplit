import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import BillSplitSendModal from 'c/billSplitSendModal';
import getWorkbench from '@salesforce/apex/BillSplitController.getWorkbench';
import calculate from '@salesforce/apex/BillSplitController.calculate';
import saveClosingReading from '@salesforce/apex/BillSplitController.saveClosingReading';
import resendNotification from '@salesforce/apex/BillSplitController.resendNotification';
import STATUS from '@salesforce/schema/Utility_Bill__c.Status__c';
import TOTAL_AMOUNT from '@salesforce/schema/Utility_Bill__c.Total_Amount__c';
import TOTAL_UNITS from '@salesforce/schema/Utility_Bill__c.Total_Units_Consumed__c';
import SUPPLY from '@salesforce/schema/Utility_Bill__c.Supply_Charge__c';
import METHOD from '@salesforce/schema/Utility_Bill__c.Split_Method__c';

const WATCHED_FIELDS = [STATUS, TOTAL_AMOUNT, TOTAL_UNITS, SUPPLY, METHOD];
const LOCKED_MESSAGES = [
    'This bill has been sent and is locked. A user with the Reopen Sent Bill permission can change it.'
];

/**
 * Orchestrator component for the bill-split workbench.
 *
 * Sits on a Utility_Bill__c record page and coordinates:
 *   - Bill summary display        (c-bill-split-bill-summary)
 *   - Sub-meter reading form      (c-bill-split-meter-reading)
 *   - Calculate / Send actions     (c-bill-split-actions)
 *   - Allocation results table     (c-bill-split-allocations)
 *   - Email notification log       (c-bill-split-email-log)
 *   - Send confirmation modal      (c-bill-split-send-modal — LightningModal)
 *   - Error / warning banners      (c-bill-split-alert)
 *
 * All Apex calls live here; children communicate via @api props (down)
 * and custom events (up).
 */
export default class BillSplitWorkbench extends LightningElement {
    @api recordId;

    data;
    busy = false;
    loaded = false;
    errors = [];
    warnings = [];
    closingValue = null;
    closingDate = null;
    statusAnnouncement = '';
    _lastSignature;

    /** Reload whenever the bill's own figures change (e.g. after a record-detail edit). */
    @wire(getRecord, { recordId: '$recordId', fields: WATCHED_FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            const f = data.fields;
            const signature = WATCHED_FIELDS.map((x) => f[x.fieldApiName].value).join('|');
            if (signature !== this._lastSignature) {
                this._lastSignature = signature;
                this.refresh();
            }
        } else if (error) {
            this.errors = [this._message(error)];
            this.loaded = true;
        }
    }

    // ------------------------------------------------------------------ view model

    get hasData() {
        return !!this.data;
    }

    get hasAllocations() {
        return this.data && this.data.allocations.length > 0;
    }

    get hasMeter() {
        return !!this.data.meter;
    }

    get isLocked() {
        return this.data.isLocked;
    }

    get lockedMessages() {
        return LOCKED_MESSAGES;
    }

    get hasNotifications() {
        return this.data.notifications.length > 0;
    }

    get uom() {
        return this.data.unitOfMeasure || '';
    }

    // ------------------------------------------------------------------ data loading

    async refresh() {
        try {
            const result = await getWorkbench({ billId: this.recordId });
            this._applyData(result);
            this.errors = [];
        } catch (e) {
            this.errors = [this._message(e)];
        } finally {
            this.loaded = true;
        }
    }

    _applyData(result) {
        this.data = result;
        const m = result.meter;
        this.closingValue =
            m && m.closingValue !== undefined && m.closingValue !== null ? m.closingValue : null;
        this.closingDate = m && m.closingDate ? m.closingDate : result.periodEnd;
    }

    // ------------------------------------------------------------------ child-event handlers

    async handleSaveReading(event) {
        const { readingValue, readingDate } = event.detail;
        this.busy = true;
        this.errors = [];
        this.warnings = [];
        try {
            const result = await saveClosingReading({
                billId: this.recordId,
                readingValue,
                readingDate
            });
            this._applyData(result);
            this._toast('Reading saved', 'The closing reading was saved.', 'success');
            this.statusAnnouncement = 'Closing reading saved successfully.';
        } catch (e) {
            this.errors = [this._message(e)];
        } finally {
            this.busy = false;
        }
    }

    async handleCalculate() {
        this.busy = true;
        this.errors = [];
        this.warnings = [];
        try {
            const result = await calculate({ billId: this.recordId });
            this._applyData(result);
            this.warnings = result.warnings || [];
            this._toast('Split calculated', 'Check the figures below before sending.', 'success');
            this.statusAnnouncement = 'Split calculation complete. Review the results below.';
        } catch (e) {
            this.errors = [this._message(e)];
        } finally {
            this.busy = false;
        }
    }

    async handleSend() {
        const result = await BillSplitSendModal.open({
            size: 'medium',
            billId: this.recordId
        });
        if (result) {
            this._applyData(result);
            this.warnings = result.warnings || [];
            const failed = result.notifications.filter((n) => n.status === 'Failed').length;
            if (result.status === 'Sent') {
                this._toast(
                    'Split sent',
                    failed > 0
                        ? failed + ' email(s) failed. Use Resend in the email log.'
                        : 'The owners have been emailed.',
                    failed > 0 ? 'warning' : 'success'
                );
                this.statusAnnouncement = 'Bill split sent to owners.';
            } else {
                this._toast('Nothing was sent', 'All emails failed. See the messages above.', 'error');
            }
        }
    }

    async handleResend(event) {
        const { notificationId } = event.detail;
        this.busy = true;
        this.errors = [];
        this.warnings = [];
        try {
            const result = await resendNotification({ billId: this.recordId, notificationId });
            this._applyData(result);
            this.warnings = result.warnings || [];
            if (this.warnings.length === 0) {
                this._toast('Email sent', 'The email was sent again.', 'success');
            }
            this.statusAnnouncement = 'Email resent.';
        } catch (e) {
            this.errors = [this._message(e)];
        } finally {
            this.busy = false;
        }
    }

    // ------------------------------------------------------------------ utilities

    _message(e) {
        if (e && e.body) {
            if (Array.isArray(e.body)) {
                return e.body.map((x) => x.message).join(' ');
            }
            if (e.body.message) {
                return e.body.message;
            }
        }
        return (e && e.message) || 'Something went wrong.';
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}