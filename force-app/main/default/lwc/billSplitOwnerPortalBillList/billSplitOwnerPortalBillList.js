import { LightningElement, api } from 'lwc';

/**
 * Bills table for a single property. Displays period, due date, total and the
 * owner's share. Fires `viewbill` with `{ billId }` and `back` for navigation.
 *
 * @example
 * <c-bill-split-owner-portal-bill-list
 *     bills={bills}
 *     selected-property={selectedProperty}
 *     onviewbill={handleViewBill}
 *     onback={handleBackToHome}>
 * </c-bill-split-owner-portal-bill-list>
 */
export default class BillSplitOwnerPortalBillList extends LightningElement {
    @api bills = [];
    @api selectedProperty;

    get propertyName() {
        return this.selectedProperty?.name || '';
    }

    get hasBills() {
        return Array.isArray(this.bills) && this.bills.length > 0;
    }

    get billRows() {
        return this.bills.map((b) => ({
            ...b,
            hasMyShare: b.myShare !== null && b.myShare !== undefined
        }));
    }

    handleViewBill(event) {
        const billId = event.currentTarget.dataset.id;
        this.dispatchEvent(
            new CustomEvent('viewbill', { detail: { billId } })
        );
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }
}
