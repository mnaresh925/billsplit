import { LightningElement, api } from 'lwc';

/**
 * Split-result table showing each unit's usage share, charges, and total.
 * Includes a totals footer row and a variance message.
 *
 * @example
 * <c-bill-split-allocations
 *     allocations={data.allocations}
 *     unit-of-measure="kL"
 *     allocated-amount={data.allocatedAmount}
 *     variance={data.variance}
 *     split-method={data.splitMethod}>
 * </c-bill-split-allocations>
 */
export default class BillSplitAllocations extends LightningElement {
    @api allocations = [];
    @api unitOfMeasure = '';
    @api allocatedAmount;
    @api variance;
    @api splitMethod;

    get rows() {
        return this.allocations.map((r) => ({
            ...r,
            tag: r.isResidual ? 'Remainder' : 'Sub-metered',
            hasTag: this.splitMethod !== 'Equal',
            tagClass: r.isResidual ? 'slds-badge slds-m-horizontal_xx-small' : 'slds-badge slds-theme_info slds-m-horizontal_xx-small'
        }));
    }

    get varianceOk() {
        return this.variance === 0 || this.variance === null || this.variance === undefined;
    }

    get varianceClass() {
        return this.varianceOk
            ? 'slds-m-top_small slds-text-color_success'
            : 'slds-m-top_small slds-text-color_error';
    }

    get notes() {
        const first = this.allocations.find((r) => r.notes);
        return first ? first.notes : '';
    }

    get hasNotes() {
        return !!this.notes;
    }
}