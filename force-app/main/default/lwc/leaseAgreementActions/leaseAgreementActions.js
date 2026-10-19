import { LightningElement, api, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import JSPDF from '@salesforce/resourceUrl/jspdf';
import getLeaseDetails from '@salesforce/apex/LeaseAgreementController.getLeaseDetails';
import markPdfGenerated from '@salesforce/apex/LeaseAgreementController.markPdfGenerated';
import sendLeaseToTenant from '@salesforce/apex/LeaseAgreementController.sendLeaseToTenant';

const MARGIN = 20;
const LINE_HEIGHT = 7;
const PAGE_BOTTOM = 280;

export default class LeaseAgreementActions extends LightningElement {
    @api recordId;
    lease;
    wiredLease;
    libraryLoaded = false;
    isBusy = false;
    error;

    @wire(getLeaseDetails, { leaseId: '$recordId' })
    handleLease(result) {
        this.wiredLease = result;
        if (result.data) {
            this.lease = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.lease = undefined;
            this.error = result.error?.body?.message || 'Unable to load the lease agreement.';
        }
    }

    renderedCallback() {
        if (this.libraryLoaded) {
            return;
        }
        this.libraryLoaded = true;
        loadScript(this, JSPDF).catch(() => {
            this.error = 'Unable to load the PDF library.';
        });
    }

    get isDisabled() {
        return !this.lease || this.isBusy;
    }

    get tenantLabel() {
        const tenant = this.lease?.Tenant__r;
        if (!tenant) {
            return '-';
        }
        return tenant.Email__c ? `${tenant.Name} (${tenant.Email__c})` : tenant.Name;
    }

    get propertyLabel() {
        const property = this.lease?.Property__r;
        return property ? property.Property_Name__c || property.Name : '-';
    }

    get fileName() {
        return `Lease Agreement - ${this.lease.Name}.pdf`;
    }

    buildPdf() {
        const { jsPDF } = window.jspdf;
        const doc = new jsPDF();
        const lease = this.lease;
        const property = lease.Property__r || {};
        const tenant = lease.Tenant__r || {};
        const width = doc.internal.pageSize.getWidth() - MARGIN * 2;
        let y = MARGIN;

        const write = (text, options = {}) => {
            doc.setFont('helvetica', options.bold ? 'bold' : 'normal');
            doc.setFontSize(options.size || 11);
            const lines = doc.splitTextToSize(String(text ?? ''), width);
            lines.forEach((line) => {
                if (y > PAGE_BOTTOM) {
                    doc.addPage();
                    y = MARGIN;
                }
                doc.text(line, options.center ? doc.internal.pageSize.getWidth() / 2 : MARGIN, y, {
                    align: options.center ? 'center' : 'left'
                });
                y += LINE_HEIGHT;
            });
        };

        const address = [property.Address__c, property.City__c, property.State__c, property.Postal_Code__c, property.Country__c]
            .filter(Boolean)
            .join(', ');

        write('LEASE AGREEMENT', { bold: true, size: 18, center: true });
        write(`Agreement No: ${lease.Name}`, { center: true });
        y += LINE_HEIGHT;
        write('Property', { bold: true, size: 13 });
        write(this.propertyLabel);
        write(address);
        y += 3;
        write('Tenant', { bold: true, size: 13 });
        write(tenant.Name);
        write([tenant.Email__c, tenant.Phone_Number__c].filter(Boolean).join(' | '));
        y += 3;
        write('Lease Details', { bold: true, size: 13 });
        write(`Agreed Monthly Rent: ${this.formatCurrency(lease.Agreed_Monthly_Rent__c)}`);
        write(`Start Date: ${this.formatDate(lease.Start_Date__c)}`);
        write(`End Date: ${this.formatDate(lease.End_Date__c)}`);
        y += 3;
        write('Terms and Conditions', { bold: true, size: 13 });
        write(lease.Terms__c || 'Standard terms apply.');
        y += LINE_HEIGHT * 2;
        write('_________________________                _________________________');
        write('Landlord Signature                                    Tenant Signature');
        return doc;
    }

    formatCurrency(value) {
        return value == null ? '-' : new Intl.NumberFormat(undefined, { minimumFractionDigits: 2 }).format(value);
    }

    formatDate(value) {
        // Salesforce dates arrive as YYYY-MM-DD, which JS parses as UTC midnight.
        return value
            ? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeZone: 'UTC' }).format(new Date(value))
            : '-';
    }

    ensureLibrary() {
        if (!window.jspdf) {
            throw new Error('The PDF library is still loading. Please try again.');
        }
    }

    async handleDownload() {
        try {
            this.ensureLibrary();
            this.isBusy = true;
            this.buildPdf().save(this.fileName);
            await markPdfGenerated({ leaseId: this.recordId });
            await this.refresh();
        } catch (e) {
            this.notifyError(e);
        } finally {
            this.isBusy = false;
        }
    }

    async handleSend() {
        try {
            this.ensureLibrary();
            this.isBusy = true;
            const dataUri = this.buildPdf().output('datauristring');
            const pdfBase64 = dataUri.substring(dataUri.indexOf(',') + 1);
            await sendLeaseToTenant({ leaseId: this.recordId, pdfBase64 });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Sent',
                    message: `Lease agreement emailed to ${this.lease.Tenant__r.Email__c}.`,
                    variant: 'success'
                })
            );
            await this.refresh();
        } catch (e) {
            this.notifyError(e);
        } finally {
            this.isBusy = false;
        }
    }

    async refresh() {
        await refreshApex(this.wiredLease);
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    }

    notifyError(e) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: e?.body?.message || e?.message || 'Something went wrong.',
                variant: 'error'
            })
        );
    }
}