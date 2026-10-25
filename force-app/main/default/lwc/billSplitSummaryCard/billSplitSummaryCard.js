import { LightningElement, api } from 'lwc';

/**
 * Reusable summary card used in review / confirmation steps of a wizard.
 * Displays an icon, title with a success checkmark, slotted body content,
 * and an optional "Edit" button that fires an `edit` event.
 *
 * @example
 * <c-bill-split-summary-card
 *     icon-name="standard:household"
 *     title="Property"
 *     step-number="1"
 *     onedit={handleReviewEdit}>
 *     <p>12 Banksia St</p>
 * </c-bill-split-summary-card>
 */
export default class BillSplitSummaryCard extends LightningElement {
    /** SLDS icon name, e.g. "standard:household". */
    @api iconName;

    /** Section title shown beside the icon. */
    @api title;

    /**
     * Step number to navigate to when the edit button is clicked.
     * If not provided the edit button is hidden.
     */
    @api stepNumber;

    /** Show the edit button only when a step number is supplied. */
    get showEditButton() {
        return this.stepNumber != null;
    }

    /** Accessible label for the edit button. */
    get editAriaLabel() {
        return 'Edit ' + (this.title || '').toLowerCase();
    }

    /** Dispatch an `edit` event with the step number so the parent can navigate. */
    handleEdit() {
        this.dispatchEvent(
            new CustomEvent('edit', {
                detail: { stepNumber: this.stepNumber }
            })
        );
    }
}