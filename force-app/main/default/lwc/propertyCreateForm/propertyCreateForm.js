import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import userId from '@salesforce/user/Id';
import createPropertyWithImages from '@salesforce/apex/PropertyController.createPropertyWithImages';

export default class PropertyCreateForm extends NavigationMixin(LightningElement) {
    userId = userId;
    acceptedFormats = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
    images = [];
    isSaving = false;
    error;

    get hasImages() {
        return this.images.length > 0;
    }

    handleUploadFinished(event) {
        const uploaded = event.detail.files.map((file) => ({
            documentId: file.documentId,
            name: file.name
        }));
        this.images = [...this.images, ...uploaded];
        this.error = undefined;
    }

    handleRemoveImage(event) {
        const documentId = event.target.name;
        this.images = this.images.filter((image) => image.documentId !== documentId);
    }

    async handleSubmit(event) {
        event.preventDefault();
        if (!this.hasImages) {
            this.error = 'Please upload at least one property image before saving.';
            return;
        }
        this.error = undefined;
        this.isSaving = true;
        try {
            const property = { sobjectType: 'Property__c', ...event.detail.fields };
            const recordId = await createPropertyWithImages({
                property,
                contentDocumentIds: this.images.map((image) => image.documentId)
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Property created successfully.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CustomEvent('success', { detail: { recordId } }));
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId, objectApiName: 'Property__c', actionName: 'view' }
            });
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Unable to create the property.';
        } finally {
            this.isSaving = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Property__c', actionName: 'list' },
            state: { filterName: 'All' }
        });
    }
}