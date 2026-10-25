import { LightningElement, api } from 'lwc';

const DELIVERY_BADGE = {
    Sent: 'slds-badge slds-theme_success',
    Failed: 'slds-badge slds-theme_error',
    Queued: 'slds-badge'
};

/**
 * Email notification log table. Shows delivery status for each recipient
 * and lets the user resend failed emails.
 *
 * @example
 * <c-bill-split-email-log
 *     notifications={data.notifications}
 *     busy={busy}
 *     onresend={handleResend}>
 * </c-bill-split-email-log>
 */
export default class BillSplitEmailLog extends LightningElement {
    @api notifications = [];
    @api busy = false;

    get rows() {
        return this.notifications.map((n) => ({
            ...n,
            badgeClass: DELIVERY_BADGE[n.status] || 'slds-badge'
        }));
    }

    handleResend(event) {
        this.dispatchEvent(
            new CustomEvent('resend', {
                detail: { notificationId: event.target.dataset.id }
            })
        );
    }
}