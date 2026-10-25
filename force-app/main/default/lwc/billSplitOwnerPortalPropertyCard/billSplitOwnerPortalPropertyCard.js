import { LightningElement, api } from 'lwc';

/**
 * Renders a single property card with its units and latest-bill snapshot.
 * Fires `viewbills` with `{ propertyId }` when the user clicks "View bills".
 *
 * @example
 * <c-bill-split-owner-portal-property-card
 *     property={p}
 *     onviewbills={handleViewBills}>
 * </c-bill-split-owner-portal-property-card>
 */
export default class BillSplitOwnerPortalPropertyCard extends LightningElement {
    @api property;

    get name() {
        return this.property?.name || '';
    }

    get address() {
        return this.property?.address || '';
    }

    get latestBill() {
        return this.property?.latestBill;
    }

    get hasLatest() {
        return !!this.property?.latestBill;
    }

    get hasMyShare() {
        const lb = this.property?.latestBill;
        return !!lb && lb.myShare !== null && lb.myShare !== undefined;
    }

    /** True when there is no latest bill AND the property data is loaded */
    get showNoBills() {
        return !!this.property && !this.property.latestBill;
    }

    get unitRows() {
        if (!this.property?.units) {
            return [];
        }
        return this.property.units.map((u) => ({
            ...u,
            boxClass: u.isMine
                ? 'slds-box slds-box_x-small unit-mine'
                : 'slds-box slds-box_x-small unit-default'
        }));
    }

    handleViewBills() {
        this.dispatchEvent(
            new CustomEvent('viewbills', {
                detail: { propertyId: this.property.propertyId }
            })
        );
    }
}
