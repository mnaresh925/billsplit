import { LightningElement, api } from 'lwc';
import { loadScript, loadStyle } from 'lightning/platformResourceLoader';
import LEAFLET from '@salesforce/resourceUrl/leaflet_1_9_4';

const NOMINATIM = 'https://nominatim.openstreetmap.org';
const MIN_GAP_MS = 1100; // Nominatim usage policy: at most 1 request per second
const TIMEOUT_MS = 6000;
const CANBERRA = [-35.2809, 149.13];
const UNAVAILABLE = 'Map lookup is unavailable. Enter the address manually.';
const STATE_NAMES = {
    'australian capital territory': 'ACT',
    'new south wales': 'NSW',
    'northern territory': 'NT',
    queensland: 'QLD',
    'south australia': 'SA',
    tasmania: 'TAS',
    victoria: 'VIC',
    'western australia': 'WA'
};
const STATE_OPTIONS = ['ACT', 'NSW', 'NT', 'QLD', 'SA', 'TAS', 'VIC', 'WA'].map((s) => ({ label: s, value: s }));

// Results are cached for the browser session (module scope is shared by all instances).
const cache = new Map();

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export default class BillSplitAddressPicker extends LightningElement {
    @api label = 'Address';

    stateOptions = STATE_OPTIONS;
    query = '';
    results = [];
    notice = '';
    busy = false;
    manual = false;
    mapReady = false;

    _address = { street: '', suburb: '', state: '', postcode: '', latitude: null, longitude: null, source: 'Manual' };
    _initStarted = false;
    _map;
    _marker;
    _lastRequestAt = 0;
    _chain = Promise.resolve();

    // ------------------------------------------------------------------ public API

    @api
    get value() {
        return this._address;
    }
    set value(v) {
        const next = { ...this._address, ...(v || {}) };
        this._address = next;
        if (this.mapReady && next.latitude != null && next.longitude != null) {
            this.placeMarker(next.latitude, next.longitude, false);
        }
    }

    /** Returns true when the address fields are valid, and shows messages when they are not. */
    @api
    reportValidity() {
        let valid = true;
        this.template.querySelectorAll('lightning-input.addr-field, lightning-combobox.addr-field').forEach((el) => {
            if (!el.reportValidity()) {
                valid = false;
            }
        });
        return valid;
    }

    // ------------------------------------------------------------------ getters

    get street() {
        return this._address.street;
    }
    get suburb() {
        return this._address.suburb;
    }
    get state() {
        return this._address.state;
    }
    get postcode() {
        return this._address.postcode;
    }
    get hasResults() {
        return this.results.length > 0;
    }
    get hasNotice() {
        return !!this.notice;
    }
    get mapClass() {
        return this.manual ? 'map slds-hide' : 'map';
    }
    get searchRowClass() {
        return this.manual ? 'slds-hide' : 'slds-m-bottom_small';
    }
    get sourceText() {
        return this._address.latitude != null && this._address.source === 'Map Pick'
            ? 'Location saved from the map.'
            : 'No map location. The address will be saved as typed.';
    }

    // ------------------------------------------------------------------ map setup

    renderedCallback() {
        if (this._initStarted) {
            return;
        }
        this._initStarted = true;
        Promise.all([loadScript(this, LEAFLET + '/leaflet.js'), loadStyle(this, LEAFLET + '/leaflet.css')])
            .then(() => this.initMap())
            .catch(() => this.fallBackToManual());
    }

    initMap() {
        const L = window.L;
        const el = this.template.querySelector('.map');
        if (!L || !el) {
            this.fallBackToManual();
            return;
        }
        const a = this._address;
        const hasPoint = a.latitude != null && a.longitude != null;
        this._map = L.map(el).setView(hasPoint ? [a.latitude, a.longitude] : CANBERRA, hasPoint ? 17 : 12);
        L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
            maxZoom: 19,
            attribution: '&copy; OpenStreetMap contributors'
        }).addTo(this._map);
        this._map.on('click', (e) => this.pickPoint(e.latlng.lat, e.latlng.lng));
        this.mapReady = true;
        if (hasPoint) {
            this.placeMarker(a.latitude, a.longitude, false);
        }
    }

    fallBackToManual() {
        this.manual = true;
        this.notice = UNAVAILABLE;
        this.setAddress({ latitude: null, longitude: null, source: 'Manual' });
    }

    markerIcon() {
        const L = window.L;
        return L.icon({
            iconUrl: LEAFLET + '/images/marker-icon.png',
            iconRetinaUrl: LEAFLET + '/images/marker-icon-2x.png',
            shadowUrl: LEAFLET + '/images/marker-shadow.png',
            iconSize: [25, 41],
            iconAnchor: [12, 41],
            popupAnchor: [1, -34],
            shadowSize: [41, 41]
        });
    }

    placeMarker(lat, lng, recentre) {
        const L = window.L;
        if (!this._map || !L) {
            return;
        }
        if (this._marker) {
            this._marker.setLatLng([lat, lng]);
        } else {
            this._marker = L.marker([lat, lng], { draggable: true, icon: this.markerIcon() }).addTo(this._map);
            this._marker.on('dragend', () => {
                const p = this._marker.getLatLng();
                this.pickPoint(p.lat, p.lng);
            });
        }
        if (recentre) {
            this._map.setView([lat, lng], Math.max(this._map.getZoom(), 17));
        }
    }

    // ------------------------------------------------------------------ Nominatim

    /** Queues requests so they are at least MIN_GAP_MS apart, caches results, and times out after 6 seconds. */
    request(url) {
        if (cache.has(url)) {
            return Promise.resolve(cache.get(url));
        }
        const run = this._chain.then(async () => {
            const wait = this._lastRequestAt + MIN_GAP_MS - Date.now();
            if (wait > 0) {
                await sleep(wait);
            }
            this._lastRequestAt = Date.now();
            const controller = new AbortController();
            const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
            try {
                const response = await fetch(url, { signal: controller.signal });
                if (!response.ok) {
                    throw new Error('HTTP ' + response.status);
                }
                const json = await response.json();
                cache.set(url, json);
                return json;
            } finally {
                clearTimeout(timer);
            }
        });
        this._chain = run.catch(() => undefined);
        return run;
    }

    handleQueryChange(event) {
        this.query = event.target.value;
    }

    handleQueryKey(event) {
        if (event.key === 'Enter') {
            this.handleSearch();
        }
    }

    async handleSearch() {
        const q = (this.query || '').trim();
        if (!q || this.busy) {
            return;
        }
        this.busy = true;
        this.notice = '';
        this.results = [];
        try {
            const url =
                NOMINATIM +
                '/search?format=jsonv2&addressdetails=1&countrycodes=au&limit=5&accept-language=en-AU&q=' +
                encodeURIComponent(q);
            const items = await this.request(url);
            if (!Array.isArray(items) || items.length === 0) {
                this.noticeAndFocus('No matching address was found. Try a different search or ' + UNAVAILABLE.toLowerCase());
                return;
            }
            this.results = items.map((item, index) => ({
                key: String(item.place_id || index),
                index,
                text: item.display_name,
                item
            }));
        } catch (e) {
            this.noticeAndFocus(UNAVAILABLE);
        } finally {
            this.busy = false;
        }
    }

    handleResultClick(event) {
        event.preventDefault();
        const index = Number(event.currentTarget.dataset.index);
        const chosen = this.results[index];
        if (!chosen) {
            return;
        }
        const lat = Number(chosen.item.lat);
        const lng = Number(chosen.item.lon);
        this.applyNominatim(chosen.item, lat, lng);
        this.placeMarker(lat, lng, true);
        this.results = [];
    }

    async pickPoint(lat, lng) {
        this.placeMarker(lat, lng, false);
        this.notice = '';
        this.busy = true;
        try {
            const url =
                NOMINATIM +
                '/reverse?format=jsonv2&addressdetails=1&zoom=18&accept-language=en-AU&lat=' +
                lat.toFixed(6) +
                '&lon=' +
                lng.toFixed(6);
            const item = await this.request(url);
            if (!item || item.error || !item.address) {
                this.noticeAndFocus('No address was found at that spot. Enter the address manually.');
                this.setAddress({ latitude: lat, longitude: lng, source: 'Map Pick' });
                return;
            }
            this.applyNominatim(item, lat, lng);
        } catch (e) {
            this.noticeAndFocus(UNAVAILABLE);
        } finally {
            this.busy = false;
        }
    }

    applyNominatim(item, lat, lng) {
        const a = item.address || {};
        const iso = (a['ISO3166-2-lvl4'] || '').replace('AU-', '');
        const state = STATE_OPTIONS.some((o) => o.value === iso) ? iso : STATE_NAMES[(a.state || '').toLowerCase()] || '';
        this.setAddress({
            street: [a.house_number, a.road].filter(Boolean).join(' '),
            suburb: a.suburb || a.city_district || a.town || a.city || a.village || '',
            state,
            postcode: a.postcode || '',
            latitude: Number(lat.toFixed(6)),
            longitude: Number(lng.toFixed(6)),
            source: 'Map Pick'
        });
    }

    noticeAndFocus(message) {
        this.notice = message;
        const first = this.template.querySelector('lightning-input.addr-field');
        if (first) {
            first.focus();
        }
    }

    // ------------------------------------------------------------------ fields and events

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.setAddress({ [field]: event.target.value });
    }

    handleManualToggle(event) {
        this.manual = event.target.checked;
        if (this.manual) {
            this.notice = '';
            this.results = [];
            // Manual entry means no coordinates are kept.
            this.setAddress({ latitude: null, longitude: null, source: 'Manual' });
        } else if (this._map) {
            // The map was hidden, so Leaflet needs to re-measure it.
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this._map.invalidateSize(), 50);
        }
    }

    setAddress(changes) {
        this._address = { ...this._address, ...changes };
        this.dispatchEvent(new CustomEvent('addresschange', { detail: { ...this._address } }));
    }

    disconnectedCallback() {
        if (this._map) {
            this._map.remove();
            this._map = null;
            this._marker = null;
        }
    }
}