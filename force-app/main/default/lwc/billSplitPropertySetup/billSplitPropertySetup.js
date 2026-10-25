import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import save from '@salesforce/apex/PropertySetupController.save';

const blankAddress = () => ({
    street: '',
    suburb: '',
    state: '',
    postcode: '',
    latitude: null,
    longitude: null,
    source: 'Manual'
});

let ownerSeq = 0;
const newOwner = () => ({
    key: 'owner-' + ++ownerSeq,
    mode: 'new',
    contactId: null,
    firstName: '',
    lastName: '',
    email: '',
    alternateEmail: '',
    unitChoice: 'all',
    role: 'Owner',
    preference: 'Primary',
    receivesBills: true
});

const addressText = (a) => [a.street, a.suburb, a.state, a.postcode].filter(Boolean).join(', ');

export default class BillSplitPropertySetup extends NavigationMixin(LightningElement) {
    step = 1;
    saving = false;
    error = '';

    steps = [
        { label: 'Property', value: '1' },
        { label: 'Units', value: '2' },
        { label: 'Owners', value: '3' },
        { label: 'Utility', value: '4' },
        { label: 'Review', value: '5' }
    ];

    statusOptions = [
        { label: 'Occupied', value: 'Occupied' },
        { label: 'Vacant', value: 'Vacant' }
    ];
    roleOptions = ['Owner', 'Co-owner', 'Tenant', 'Agent'].map((v) => ({ label: v, value: v }));
    preferenceOptions = [
        { label: 'Primary email', value: 'Primary' },
        { label: 'Alternate email', value: 'Alternate' },
        { label: 'Both emails', value: 'Both' }
    ];
    modeOptions = [
        { label: 'New contact', value: 'new' },
        { label: 'Existing contact', value: 'existing' }
    ];
    frequencyOptions = ['Quarterly', 'Monthly', 'Half-yearly', 'Annual'].map((v) => ({ label: v, value: v }));
    pickerDisplay = { additionalFields: ['Email'] };
    pickerMatching = { primaryField: { fieldPath: 'Name' }, additionalFields: [{ fieldPath: 'Email' }] };

    property = { displayName: '', councilName: '', ratesAssessmentNo: '', address: blankAddress() };
    units = [
        { label: 'Unit A', sameAsProperty: true, status: 'Occupied', address: blankAddress() },
        { label: 'Unit B', sameAsProperty: false, status: 'Occupied', address: blankAddress() }
    ];
    owners = [newOwner()];
    utility = {
        accountNumber: '',
        provider: '',
        billingFrequency: 'Quarterly',
        hasSubMeter: true,
        meterName: '',
        meterUnit: '0',
        baselineValue: null,
        baselineDate: null
    };

    // ------------------------------------------------------------------ step flags

    get currentStep() {
        return String(this.step);
    }
    get isStep1() {
        return this.step === 1;
    }
    get isStep2() {
        return this.step === 2;
    }
    get isStep3() {
        return this.step === 3;
    }
    get isStep4() {
        return this.step === 4;
    }
    get isStep5() {
        return this.step === 5;
    }
    get hasBack() {
        return this.step > 1;
    }
    get hasNext() {
        return this.step < 5;
    }
    get hasError() {
        return !!this.error;
    }

    // ------------------------------------------------------------------ view models

    get unitRows() {
        return this.units.map((u, index) => ({
            ...u,
            index,
            number: index + 1,
            showAddress: !u.sameAsProperty,
            addressTitle: (u.label || 'Unit ' + (index + 1)) + ' address',
            cardClass: 'slds-box slds-m-bottom_medium ' + (index === 0 ? 'unit-card-a' : 'unit-card-b'),
            badgeClass: index === 0 ? 'slds-badge slds-badge_inverse' : 'slds-badge'
        }));
    }

    get unitChoiceOptions() {
        return [
            { label: 'Whole property', value: 'all' },
            { label: this.units[0].label || 'Unit 1', value: '0' },
            { label: this.units[1].label || 'Unit 2', value: '1' }
        ];
    }

    get meterUnitOptions() {
        return [
            { label: this.units[0].label || 'Unit 1', value: '0' },
            { label: this.units[1].label || 'Unit 2', value: '1' }
        ];
    }

    get ownerRows() {
        const options = this.unitChoiceOptions;
        const canRemove = this.owners.length > 1;
        return this.owners.map((o, idx) => {
            const fullName = [o.firstName, o.lastName].filter(Boolean).join(' ');
            const hasIdentity = o.mode === 'new' && !!(o.firstName || o.lastName);
            return {
                ...o,
                isNew: o.mode === 'new',
                isExisting: o.mode === 'existing',
                unitOptions: options,
                canRemove,
                showIdentity: hasIdentity,
                identityName: fullName || 'New contact',
                identityEmail: o.email || '',
                showAlternateEmail: o.preference === 'Alternate' || o.preference === 'Both',
                ariaLabel: 'Owner ' + (idx + 1) + (fullName ? ': ' + fullName : ''),
                removeLabel: 'Remove ' + (fullName || 'this owner')
            };
        });
    }

    get reviewUnits() {
        return this.units.map((u, i) => ({
            key: 'u' + i,
            label: u.label || 'Unit ' + (i + 1),
            status: u.status,
            address: u.sameAsProperty ? 'Same address as the property' : addressText(u.address)
        }));
    }

    get reviewOwners() {
        const choice = this.unitChoiceOptions;
        return this.owners.map((o) => {
            const name =
                o.mode === 'existing'
                    ? 'Existing contact'
                    : [o.firstName, o.lastName].filter(Boolean).join(' ') || 'New contact';
            const unit = choice.find((c) => c.value === o.unitChoice);
            return {
                key: o.key,
                name,
                role: o.role,
                detail:
                    (unit ? unit.label : '') +
                    ' · Bills to ' +
                    o.preference.toLowerCase() +
                    ' email' +
                    (o.receivesBills ? '' : ' · Does not receive bills')
            };
        });
    }

    get reviewPropertyAddress() {
        return addressText(this.property.address);
    }

    get reviewUtility() {
        const u = this.utility;
        const lines = [
            {
                key: 'acc',
                text: 'Account ' + u.accountNumber + (u.provider ? ' with ' + u.provider : '')
            },
            {
                key: 'freq',
                text: 'Billed ' + u.billingFrequency.toLowerCase() + ', measured in kL'
            }
        ];
        if (u.hasSubMeter) {
            const unit = this.meterUnitOptions.find((o) => o.value === u.meterUnit);
            lines.push({
                key: 'meter',
                text:
                    'Sub-meter ' +
                    u.meterName +
                    ' serves ' +
                    (unit ? unit.label : '') +
                    ', baseline ' +
                    u.baselineValue +
                    ' kL on ' +
                    u.baselineDate
            });
        } else {
            lines.push({
                key: 'meter',
                text: 'No sub-meter — bills can only be split equally.'
            });
        }
        return lines;
    }

    get saveLabel() {
        return this.saving ? 'Saving\u2026' : 'Save property';
    }

    // ------------------------------------------------------------------ property step

    handlePropertyField(event) {
        this.property = { ...this.property, [event.target.dataset.field]: event.target.value };
    }

    handlePropertyAddress(event) {
        this.property = { ...this.property, address: event.detail };
    }

    // ------------------------------------------------------------------ unit step

    handleUnitField(event) {
        const index = Number(event.target.dataset.index);
        const field = event.target.dataset.field;
        const value = field === 'sameAsProperty' ? event.target.checked : event.target.value;
        this.units = this.units.map((u, i) => (i === index ? { ...u, [field]: value } : u));
    }

    handleUnitAddress(event) {
        const index = Number(event.target.dataset.index);
        this.units = this.units.map((u, i) => (i === index ? { ...u, address: event.detail } : u));
    }

    // ------------------------------------------------------------------ owner step

    handleAddOwner() {
        this.owners = [...this.owners, newOwner()];
    }

    /**
     * Remove an owner with a confirmation dialog to prevent accidental data loss.
     */
    async handleRemoveOwner(event) {
        const key = event.target.dataset.key || event.currentTarget.dataset.key;
        if (this.owners.length <= 1) {
            return;
        }
        const owner = this.owners.find((o) => o.key === key);
        const name =
            owner && owner.lastName
                ? [owner.firstName, owner.lastName].filter(Boolean).join(' ')
                : 'this owner';

        const confirmed = await LightningConfirm.open({
            message: `Are you sure you want to remove ${name}? All entered data for this owner will be lost.`,
            variant: 'headerless',
            label: 'Remove owner?'
        });
        if (confirmed) {
            this.owners = this.owners.filter((o) => o.key !== key);
        }
    }

    handleOwnerField(event) {
        const key = event.target.dataset.key;
        const field = event.target.dataset.field;
        const type = event.target.type;
        const value = type === 'checkbox' || type === 'toggle' ? event.target.checked : event.target.value;
        this.updateOwner(key, { [field]: value });
    }

    handleOwnerMode(event) {
        this.updateOwner(event.target.dataset.key, { mode: event.detail.value, contactId: null });
    }

    handleContactPick(event) {
        this.updateOwner(event.target.dataset.key, { contactId: event.detail.recordId || null });
    }

    updateOwner(key, changes) {
        this.owners = this.owners.map((o) => (o.key === key ? { ...o, ...changes } : o));
    }

    /** Allow the ghost "add" card to be activated with Enter or Space for accessibility. */
    handleGhostCardKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleAddOwner();
        }
    }

    // ------------------------------------------------------------------ utility step

    handleUtilityField(event) {
        const field = event.target.dataset.field;
        const type = event.target.type;
        const value = type === 'checkbox' || type === 'toggle' ? event.target.checked : event.target.value;
        this.utility = { ...this.utility, [field]: value };
    }

    get showMeterFields() {
        return this.utility.hasSubMeter;
    }

    // ------------------------------------------------------------------ navigation and validation

    /**
     * Smoothly scroll the error banner (or the first invalid field) into view
     * after validation fails.
     */
    scrollToError() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const el = this.template.querySelector('[role="alert"]');
            if (el) {
                el.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
        }, 100);
    }

    inputsValid() {
        let ok = true;
        this.template.querySelectorAll('.req').forEach((el) => {
            if (typeof el.reportValidity === 'function' && !el.reportValidity()) {
                ok = false;
            }
        });
        this.template.querySelectorAll('c-bill-split-address-picker').forEach((el) => {
            if (!el.reportValidity()) {
                ok = false;
            }
        });
        return ok;
    }

    stepError() {
        if (this.step === 2) {
            const [a, b] = this.units.map((u) => (u.label || '').trim().toLowerCase());
            if (a && a === b) {
                return 'The two units need different labels.';
            }
        }
        if (this.step === 3) {
            for (const o of this.owners) {
                if (o.mode === 'existing' && !o.contactId) {
                    return 'Choose a contact for every owner you marked as an existing contact.';
                }
                if (o.mode === 'new' && o.preference !== 'Primary' && !o.alternateEmail) {
                    return 'An owner who receives bills at the alternate email needs an alternate email address.';
                }
            }
            if (!this.owners.some((o) => o.receivesBills)) {
                return 'At least one owner needs to receive bills.';
            }
        }
        return '';
    }

    handleNext() {
        this.error = '';
        if (!this.inputsValid()) {
            return;
        }
        const problem = this.stepError();
        if (problem) {
            this.error = problem;
            this.scrollToError();
            return;
        }
        this.step += 1;
    }

    handleBack() {
        this.error = '';
        this.step -= 1;
    }

    /**
     * Cancel with a confirmation dialog so the user does not accidentally
     * discard a partially-filled wizard.
     */
    async handleCancel() {
        const confirmed = await LightningConfirm.open({
            message: 'You have unsaved changes. Are you sure you want to leave?',
            variant: 'headerless',
            label: 'Discard changes?'
        });
        if (confirmed) {
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: { objectApiName: 'Property__c', actionName: 'list' },
                state: { filterName: 'Recent' }
            });
        }
    }

    /**
     * Jump directly to a specific step from the review summary cards.
     * Fired by the `edit` event on `c-bill-split-summary-card`.
     */
    handleReviewEdit(event) {
        this.error = '';
        this.step = Number(event.detail.stepNumber);
    }

    // ------------------------------------------------------------------ save

    buildPayload() {
        const p = this.property;
        const u = this.utility;
        return {
            property: {
                displayName: p.displayName,
                councilName: p.councilName,
                ratesAssessmentNo: p.ratesAssessmentNo,
                address: p.address
            },
            units: this.units.map((x) => ({
                label: x.label,
                sameAsProperty: x.sameAsProperty,
                status: x.status,
                address: x.sameAsProperty ? null : x.address
            })),
            owners: this.owners.map((o) => ({
                contactId: o.mode === 'existing' ? o.contactId : null,
                newContact:
                    o.mode === 'new'
                        ? {
                              firstName: o.firstName,
                              lastName: o.lastName,
                              email: o.email,
                              alternateEmail: o.alternateEmail
                          }
                        : null,
                unitIndex: o.unitChoice === 'all' ? null : Number(o.unitChoice),
                role: o.role,
                preference: o.preference,
                receivesBills: o.receivesBills
            })),
            utility: {
                utilityType: 'Water',
                provider: u.provider,
                accountNumber: u.accountNumber,
                billingFrequency: u.billingFrequency,
                unitOfMeasure: 'kL',
                hasSubMeter: u.hasSubMeter,
                meterName: u.hasSubMeter ? u.meterName : null,
                meterUnitIndex: u.hasSubMeter ? Number(u.meterUnit) : null,
                baselineValue: u.hasSubMeter ? Number(u.baselineValue) : null,
                baselineDate: u.hasSubMeter ? u.baselineDate : null
            }
        };
    }

    async handleSave() {
        this.error = '';
        this.saving = true;
        try {
            const result = await save({ payloadJson: JSON.stringify(this.buildPayload()) });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Property saved',
                    message: 'The property, units, owners and utility account were created.',
                    variant: 'success'
                })
            );
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: result.propertyId, objectApiName: 'Property__c', actionName: 'view' }
            });
        } catch (e) {
            this.error = (e && e.body && e.body.message) || (e && e.message) || 'The property could not be saved.';
            this.scrollToError();
        } finally {
            this.saving = false;
        }
    }
}