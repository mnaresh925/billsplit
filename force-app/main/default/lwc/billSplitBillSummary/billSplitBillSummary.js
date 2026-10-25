import { LightningElement, api } from 'lwc';

const STATUS_BADGE = {
    Draft: 'slds-badge',
    Calculated: 'slds-badge slds-theme_info',
    Sent: 'slds-badge slds-theme_success'
};

/**
 * Read-only summary grid displaying the bill's key metrics.
 *
 * @example
 * <c-bill-split-bill-summary
 *     status="Calculated"
 *     period-start={data.periodStart}
 *     period-end={data.periodEnd}
 *     total-amount={data.totalAmount}
 *     total-units={data.totalUnits}
 *     usage-charge={data.usageCharge}
 *     supply-charge={data.supplyCharge}
 *     split-method={data.splitMethod}
 *     unit-of-measure="kL">
 * </c-bill-split-bill-summary>
 */
export default class BillSplitBillSummary extends LightningElement {
    @api status;
    @api periodStart;
    @api periodEnd;
    @api totalAmount;
    @api totalUnits;
    @api usageCharge;
    @api supplyCharge;
    @api splitMethod;
    @api unitOfMeasure;

    get statusClass() {
        return STATUS_BADGE[this.status] || 'slds-badge';
    }
}