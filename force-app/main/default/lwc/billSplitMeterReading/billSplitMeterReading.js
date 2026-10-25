import { LightningElement, api } from 'lwc';

/**
 * Sub-meter closing-reading form. Displays the opening reading and accepts
 * a new closing value and date. Fires `savereading` when the user clicks Save.
 *
 * Uses getter/setter @api properties for closingValue and closingDate so
 * the parent can push fresh data (e.g. after a successful save) while the
 * component still lets the user edit freely.
 *
 * @example
 * <c-bill-split-meter-reading
 *     meter-name="M-001"
 *     unit-name="Unit A"
 *     opening-value={meter.openingValue}
 *     opening-date={meter.openingDate}
 *     closing-value={closingVal}
 *     closing-date={closingDt}
 *     can-edit
 *     onsavereading={handleSaveReading}>
 * </c-bill-split-meter-reading>
 */
export default class BillSplitMeterReading extends LightningElement {
    @api meterName;
    @api unitName;
    @api openingValue;
    @api openingDate;
    @api canEdit = false;
    @api busy = false;
    @api needsReading = false;

    /** Internal form state kept in sync with the public @api via setters. */
    inputValue;
    inputDate;

    @api
    get closingValue() {
        return this.inputValue;
    }
    set closingValue(val) {
        this.inputValue = val;
    }

    @api
    get closingDate() {
        return this.inputDate;
    }
    set closingDate(val) {
        this.inputDate = val;
    }

    // ------------------------------------------------------------------ computed

    get inputsDisabled() {
        return !this.canEdit;
    }

    get saveDisabled() {
        return this.busy || !this.canEdit;
    }

    get helpMessage() {
        return this.needsReading
            ? 'Enter the sub-meter reading taken at the end of the billing period, then calculate.'
            : '';
    }

    get showHelp() {
        return !!this.helpMessage;
    }

    // ------------------------------------------------------------------ handlers

    handleValueChange(event) {
        this.inputValue = event.target.value;
    }

    handleDateChange(event) {
        this.inputDate = event.target.value;
    }

    handleSave() {
        const inputs = [...this.template.querySelectorAll('.reading-input')];
        if (!inputs.every((i) => i.reportValidity())) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('savereading', {
                detail: {
                    readingValue: Number(this.inputValue),
                    readingDate: this.inputDate
                }
            })
        );
    }
}