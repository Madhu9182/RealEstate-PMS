import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import NAME from '@salesforce/schema/Property__c.Property_Name__c';
import ADDRESS from '@salesforce/schema/Property__c.Address__c';
import CITY from '@salesforce/schema/Property__c.City__c';
import STATE from '@salesforce/schema/Property__c.State__c';
import POSTAL_CODE from '@salesforce/schema/Property__c.Postal_Code__c';
import COUNTRY from '@salesforce/schema/Property__c.Country__c';
import LATITUDE from '@salesforce/schema/Property__c.Location__c';
import LONGITUDE from '@salesforce/schema/Property__c.Location__c';

const FIELDS = [NAME, ADDRESS, CITY, STATE, POSTAL_CODE, COUNTRY];
const OPTIONAL_FIELDS = [LATITUDE, LONGITUDE];

export default class PropertyMap extends LightningElement {
    @api recordId;
    mapMarkers;
    isPending = false;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS, optionalFields: OPTIONAL_FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            const latitude = getFieldValue(data, LATITUDE);
            const longitude = getFieldValue(data, LONGITUDE);
            const street = getFieldValue(data, ADDRESS);
            const city = getFieldValue(data, CITY);
            const state = getFieldValue(data, STATE);
            const postalCode = getFieldValue(data, POSTAL_CODE);
            const country = getFieldValue(data, COUNTRY);
            const hasCoordinates = latitude != null && longitude != null;
            this.isPending = !hasCoordinates;
            this.mapMarkers = [
                {
                    location: hasCoordinates
                        ? { Latitude: latitude, Longitude: longitude }
                        : { Street: street, City: city, State: state, PostalCode: postalCode, Country: country },
                    title: getFieldValue(data, NAME),
                    description: [street, city, state, postalCode, country].filter(Boolean).join(', ')
                }
            ];
            this.error = undefined;
        } else if (error) {
            this.mapMarkers = undefined;
            this.error = error?.body?.message || 'Unable to load the property location.';
        }
    }
}