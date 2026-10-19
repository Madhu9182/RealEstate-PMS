import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getProperties from '@salesforce/apex/PropertyController.getProperties';

const PAGE_SIZE = 25;
const ALL = '';
const NUMERIC_FILTERS = ['minPrice', 'maxPrice', 'distanceKm'];

const COLUMNS = [
    {
        label: 'Property',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'displayName' }, target: '_self' }
    },
    { label: 'City', fieldName: 'City__c' },
    { label: 'Type', fieldName: 'Type__c' },
    { label: 'Rent', fieldName: 'Price__c', type: 'currency' },
    { label: 'Status', fieldName: 'Status__c' },
    { label: 'Furnishing', fieldName: 'Furnishing_Status__c' },
    { label: 'Tenant', fieldName: 'tenantName' }
];

const emptyFilters = () => ({
    minPrice: null,
    maxPrice: null,
    status: ALL,
    furnishingStatus: ALL,
    distanceKm: null
});

export default class PropertyList extends NavigationMixin(LightningElement) {
    columns = COLUMNS;
    rows = [];
    filters = emptyFilters();
    appliedFilter = null;
    totalCount = 0;
    pageNumber = 1;
    isLoading = false;
    error;

    statusOptions = [
        { label: 'All', value: ALL },
        { label: 'Available', value: 'Available' },
        { label: 'Occupied', value: 'Occupied' }
    ];

    furnishingOptions = [
        { label: 'All', value: ALL },
        { label: 'Furnished', value: 'Furnished' },
        { label: 'Semi Furnished', value: 'Semi Furnished' },
        { label: 'Unfurnished', value: 'Unfurnished' }
    ];

    connectedCallback() {
        this.loadPage('first');
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.totalCount / PAGE_SIZE));
    }

    get isFirstPage() {
        return this.pageNumber <= 1 || this.isLoading;
    }

    get isLastPage() {
        return this.pageNumber >= this.totalPages || this.isLoading;
    }

    get isEmpty() {
        return !this.isLoading && this.rows.length === 0;
    }

    get rowNumberOffset() {
        return (this.pageNumber - 1) * PAGE_SIZE;
    }

    handleFilterChange(event) {
        const { name, value } = event.target;
        const isNumeric = NUMERIC_FILTERS.includes(name);
        this.filters = { ...this.filters, [name]: isNumeric && value === '' ? null : value };
    }

    async handleApply() {
        this.error = undefined;
        const { minPrice, maxPrice, status, furnishingStatus, distanceKm } = this.filters;
        const filter = {
            minPrice: minPrice != null ? Number(minPrice) : null,
            maxPrice: maxPrice != null ? Number(maxPrice) : null,
            status: status || null,
            furnishingStatus: furnishingStatus || null,
            distanceKm: distanceKm != null ? Number(distanceKm) : null
        };
        if (filter.minPrice != null && filter.maxPrice != null && filter.minPrice > filter.maxPrice) {
            this.error = 'Min Price cannot be greater than Max Price.';
            return;
        }
        if (filter.distanceKm != null) {
            try {
                const coords = await this.getUserLocation();
                filter.latitude = coords.latitude;
                filter.longitude = coords.longitude;
            } catch {
                this.error = 'Unable to get your location. Please allow location access to filter by distance.';
                return;
            }
        }
        this.appliedFilter = filter;
        this.loadPage('first');
    }

    handleReset() {
        this.filters = emptyFilters();
        this.appliedFilter = null;
        this.error = undefined;
        this.loadPage('first');
    }

    handlePage(event) {
        this.loadPage(event.target.dataset.direction);
    }

    handleNewProperty() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Property__c', actionName: 'new' }
        });
    }

    getUserLocation() {
        return new Promise((resolve, reject) => {
            if (!navigator.geolocation) {
                reject(new Error('Geolocation not supported'));
                return;
            }
            navigator.geolocation.getCurrentPosition(
                (position) => resolve(position.coords),
                (err) => reject(err),
                { enableHighAccuracy: false, timeout: 10000 }
            );
        });
    }

    async loadPage(direction) {
        let cursorId = null;
        if (direction === 'next' && this.rows.length) {
            cursorId = this.rows[this.rows.length - 1].Id;
        } else if (direction === 'previous' && this.rows.length) {
            cursorId = this.rows[0].Id;
        }

        this.isLoading = true;
        try {
            const result = await getProperties({
                filter: this.appliedFilter,
                direction,
                cursorId
            });
            this.totalCount = result.totalCount;
            this.rows = result.records.map((rec) => ({
                ...rec,
                recordUrl: `/${rec.Id}`,
                displayName: rec.Property_Name__c || rec.Name,
                tenantName: rec.Tenant__r ? rec.Tenant__r.Name : ''
            }));
            this.pageNumber = this.nextPageNumber(direction);
            this.error = undefined;
        } catch (e) {
            this.rows = [];
            this.totalCount = 0;
            this.pageNumber = 1;
            this.error = e?.body?.message || e?.message || 'Unable to load properties.';
        } finally {
            this.isLoading = false;
        }
    }

    nextPageNumber(direction) {
        switch (direction) {
            case 'next':
                return Math.min(this.pageNumber + 1, this.totalPages);
            case 'previous':
                return Math.max(this.pageNumber - 1, 1);
            case 'last':
                return this.totalPages;
            default:
                return 1;
        }
    }
}