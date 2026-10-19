import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getPropertyImages from '@salesforce/apex/PropertyController.getPropertyImages';

// Download URL renders any image type; thumbnail renditions are not generated for formats like webp.
const IMAGE_URL = '/sfc/servlet.shepherd/version/download/';

export default class PropertyImageUpload extends LightningElement {
    @api recordId;
    acceptedFormats = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
    images = [];
    wiredImages;

    @wire(getPropertyImages, { propertyId: '$recordId' })
    handleImages(result) {
        this.wiredImages = result;
        if (result.data) {
            this.images = result.data.map((version) => ({
                ...version,
                thumbnailUrl: IMAGE_URL + version.Id
            }));
        }
    }

    get hasImages() {
        return this.images.length > 0;
    }

    handleUploadFinished() {
        return refreshApex(this.wiredImages);
    }
}