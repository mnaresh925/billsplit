import { LightningElement, api } from 'lwc';

/**
 * Single-bill detail view with summary metrics and allocation breakdown table.
 * Fires `back` event for navigation.
 *
 * @example
 * <c-bill-split-owner-portal-bill-detail
 *     bill={detail}
 *     onback={handleBackToBills}>
 * </c-bill-split-owner-portal-bill-detail>
 */
export default class BillSplitOwnerPortalBillDetail extends LightningElement {
    @api bill;

    get hasMyShare() {
        return !!this.bill && this.bill.myShare !== null && this.bill.myShare !== undefined;
    }

    get hasSupply() {
        return !!this.bill && !!this.bill.supplyCharge;
    }

    get hasNotes() {
        return !!this.bill && !!this.bill.notes;
    }

    get allocationRows() {
        if (!this.bill?.allocations) {
            return [];
        }
        return this.bill.allocations.map((a) => ({
            ...a,
            rowClass: a.isMine ? 'mine-row' : '',
            tag: a.isSubmetered ? 'Sub-metered' : '',
            hasTag: !!a.isSubmetered,
            hasReadings:
                a.isSubmetered &&
                a.openingReading !== null &&
                a.openingReading !== undefined &&
                a.closingReading !== null &&
                a.closingReading !== undefined
        }));
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }
}
