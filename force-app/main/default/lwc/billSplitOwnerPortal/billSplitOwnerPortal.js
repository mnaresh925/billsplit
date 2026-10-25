import { LightningElement } from 'lwc';
import getMyProperties from '@salesforce/apex/OwnerPortalController.getMyProperties';
import getBills from '@salesforce/apex/OwnerPortalController.getBills';
import getBillDetail from '@salesforce/apex/OwnerPortalController.getBillDetail';

const VIEW_HOME = 'home';
const VIEW_BILLS = 'bills';
const VIEW_DETAIL = 'detail';

/**
 * Owner Portal orchestrator. Manages view routing and data loading.
 * Rendering is delegated to child components:
 * - c-bill-split-owner-portal-property-card (one per property)
 * - c-bill-split-owner-portal-bill-list (bills table)
 * - c-bill-split-owner-portal-bill-detail (single bill breakdown)
 */
export default class BillSplitOwnerPortal extends LightningElement {
    view = VIEW_HOME;
    loading = true;
    errors = [];
    statusAnnouncement = '';

    properties = [];
    selectedProperty;
    bills = [];
    detail;

    connectedCallback() {
        this.loadProperties();
    }

    // ------------------------------------------------------------------ view flags

    get hasErrors() {
        return this.errors.length > 0;
    }

    get isHome() {
        return !this.hasErrors && this.view === VIEW_HOME;
    }

    get isBills() {
        return !this.hasErrors && this.view === VIEW_BILLS;
    }

    get isDetail() {
        return !this.hasErrors && this.view === VIEW_DETAIL;
    }

    get hasProperties() {
        return !this.hasErrors && this.properties.length > 0;
    }

    get showEmptyHome() {
        return this.isHome && !this.loading && !this.hasProperties;
    }

    // ------------------------------------------------------------------ view models

    get propertyCards() {
        return this.properties.map((p) => ({
            ...p,
            hasLatest: !!p.latestBill,
            hasMyShare: !!p.latestBill && p.latestBill.myShare !== null && p.latestBill.myShare !== undefined,
            unitRows: p.units.map((u) => ({
                ...u,
                unitClass: u.isMine ? 'unit mine' : 'unit'
            }))
        }));
    }

    // ------------------------------------------------------------------ data loading

    async loadProperties() {
        this.loading = true;
        this.errors = [];
        try {
            this.properties = await getMyProperties();
            this._announce('Properties loaded');
        } catch (e) {
            this.errors = [this._message(e)];
        } finally {
            this.loading = false;
        }
    }

    async handleViewBills(event) {
        const propertyId = event.detail.propertyId;
        this.selectedProperty = this.properties.find((p) => p.propertyId === propertyId);
        this.loading = true;
        this.errors = [];
        try {
            this.bills = await getBills({ propertyId });
            this.view = VIEW_BILLS;
            this._announce(`Bills loaded for ${this.selectedProperty?.name || 'property'}`);
        } catch (e) {
            this.errors = [this._message(e)];
        } finally {
            this.loading = false;
        }
    }

    async handleViewBill(event) {
        const billId = event.detail.billId;
        this.loading = true;
        this.errors = [];
        try {
            this.detail = await getBillDetail({ billId });
            this.view = VIEW_DETAIL;
            this._announce('Bill detail loaded');
        } catch (e) {
            this.errors = [this._message(e)];
        } finally {
            this.loading = false;
        }
    }

    handleBackToHome() {
        this.errors = [];
        this.view = VIEW_HOME;
        this._announce('Returned to properties');
    }

    handleBackToBills() {
        this.errors = [];
        this.view = VIEW_BILLS;
        this._announce('Returned to bills');
    }

    // ------------------------------------------------------------------ helpers

    _announce(text) {
        // Clear then set to ensure screen readers re-announce even if the same text
        this.statusAnnouncement = '';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.statusAnnouncement = text;
        }, 100);
    }

    _message(e) {
        if (e && e.body) {
            if (Array.isArray(e.body)) {
                return e.body.map((x) => x.message).join(' ');
            }
            if (e.body.message) {
                return e.body.message;
            }
        }
        return (e && e.message) || 'Something went wrong. Try again.';
    }
}