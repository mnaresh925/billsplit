import { LightningElement, api } from 'lwc';

/**
 * Action button bar for the bill workbench.
 * Fires `calculate` and `send` custom events; the parent wires the Apex calls.
 *
 * @example
 * <c-bill-split-actions
 *     can-calculate
 *     can-send
 *     has-allocations
 *     oncalculate={handleCalculate}
 *     onsend={handleSend}>
 * </c-bill-split-actions>
 */
export default class BillSplitActions extends LightningElement {
    @api canCalculate = false;
    @api canSend = false;
    @api busy = false;
    @api hasAllocations = false;

    get calculateLabel() {
        return this.hasAllocations ? 'Recalculate' : 'Calculate split';
    }

    get calculateDisabled() {
        return this.busy || !this.canCalculate;
    }

    handleCalculate() {
        this.dispatchEvent(new CustomEvent('calculate'));
    }

    handleSend() {
        this.dispatchEvent(new CustomEvent('send'));
    }
}