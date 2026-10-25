import LightningModal from 'lightning/modal';
import { api } from 'lwc';
import getSendPreview from '@salesforce/apex/BillSplitController.getSendPreview';
import sendBill from '@salesforce/apex/BillSplitController.sendBill';

/**
 * Send-confirmation modal built on LightningModal (API 55+).
 *
 * Opened programmatically by the parent:
 *   const result = await BillSplitSendModal.open({ size: 'medium', billId: id });
 *   if (result) { // result is the refreshed WorkbenchData }
 *
 * The modal loads its own preview via Apex and handles the send call internally.
 * Returns the WorkbenchData result on success, or null on cancel.
 */
export default class BillSplitSendModal extends LightningModal {
    /** Set by the caller via .open({ billId }). */
    @api billId;

    preview;
    loading = true;
    sending = false;
    sendError = '';

    async connectedCallback() {
        try {
            this.preview = await getSendPreview({ billId: this.billId });
        } catch (e) {
            this.sendError = this._message(e);
        } finally {
            this.loading = false;
        }
    }

    // ------------------------------------------------------------------ computed

    get sendErrorMessages() {
        return this.sendError ? [this.sendError] : [];
    }

    get hasBlockers() {
        return !!this.preview && this.preview.blockers.length > 0;
    }

    get hasWarnings() {
        return !!this.preview && this.preview.warnings.length > 0;
    }

    get sendBlocked() {
        return !this.preview || this.preview.blockers.length > 0 || this.preview.recipients.length === 0;
    }

    get confirmDisabled() {
        return this.sending || this.loading || this.sendBlocked;
    }

    get confirmLabel() {
        return this.sending ? 'Sending\u2026' : 'Send emails';
    }

    get recipientSummary() {
        const count = this.preview ? this.preview.recipients.length : 0;
        return `${count} email(s) will be sent to:`;
    }

    // ------------------------------------------------------------------ handlers

    handleCancel() {
        if (!this.sending) {
            this.close(null);
        }
    }

    async handleConfirm() {
        this.sending = true;
        this.sendError = '';
        try {
            const result = await sendBill({ billId: this.billId });
            this.close(result);
        } catch (e) {
            this.sendError = this._message(e);
        } finally {
            this.sending = false;
        }
    }

    // ------------------------------------------------------------------ util

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
}