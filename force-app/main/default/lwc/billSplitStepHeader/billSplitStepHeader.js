import { LightningElement, api } from 'lwc';

/**
 * Reusable wizard-step header that shows an icon, title, optional description,
 * and an optional "Step N of M" badge.  Designed to sit at the top of each
 * step inside a multi-step form or wizard.
 *
 * @example
 * <c-bill-split-step-header
 *     icon-name="standard:address"
 *     title="Property details"
 *     description="Enter the main address and council info."
 *     step-number="1"
 *     total-steps="5">
 * </c-bill-split-step-header>
 */
export default class BillSplitStepHeader extends LightningElement {
    /** SLDS icon name, e.g. "standard:address". */
    @api iconName;

    /** Heading text shown next to the icon. */
    @api title;

    /** Optional helper text shown below the heading. */
    @api description;

    /** Current step number (displayed in the badge). */
    @api stepNumber;

    /** Total number of steps (displayed in the badge). */
    @api totalSteps;

    /** Show the step badge only when both stepNumber and totalSteps are supplied. */
    get showStepCount() {
        return this.stepNumber != null && this.totalSteps != null;
    }
}