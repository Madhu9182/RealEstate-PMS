@IsTest
private class GeocodingServiceTest {
    @IsTest
    static void returnsNullForErrorsAndEmptyResults() {
        Test.startTest();
        Assert.isNull(GeocodingService.geocode(''));
        Test.setMock(HttpCalloutMock.class, new TestDataFactory.GeocodeMock(500, 'error'));
        Assert.isNull(GeocodingService.geocode('Somewhere'));
        Test.setMock(HttpCalloutMock.class, new TestDataFactory.GeocodeMock(200, '[]'));
        Assert.isNull(GeocodingService.geocode('Nowhere'));
        Test.setMock(HttpCalloutMock.class, new TestDataFactory.GeocodeMock(200, 'not json'));
        Assert.isNull(GeocodingService.geocode('Broken'));
        Test.stopTest();
    }

    @IsTest
    static void buildsAddressWithoutBlankParts() {
        Property__c p = new Property__c(Address__c = 'Line 1\nLine 2', City__c = 'Pune', Country__c = 'India');
        Assert.areEqual('Line 1 Line 2, Pune, India', GeocodingService.buildAddress(p));
    }

    private class FallbackMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            // Only the broader city-level query (without the street line) resolves.
            res.setBody(req.getEndpoint().contains('Street') ? '[]' : '[{"lat":"17.4","lon":"78.3"}]');
            return res;
        }
    }

    @IsTest
    static void fallsBackToBroaderAddress() {
        Test.setMock(HttpCalloutMock.class, new FallbackMock());
        Property__c p = TestDataFactory.buildProperty('Fallback');
        p.Address__c = 'Unknown Street';
        Test.startTest();
        Location loc = GeocodingService.geocodeWithFallback(p);
        Test.stopTest();
        Assert.areEqual(17.4, loc.getLatitude());
    }

    @IsTest
    static void processesMoreThanOneChunk() {
        Test.setMock(HttpCalloutMock.class, TestDataFactory.successMock());
        List<Property__c> props = new List<Property__c>();
        for (Integer i = 0; i < GeocodingService.CHUNK_SIZE + 5; i++) {
            props.add(TestDataFactory.buildProperty('P' + i));
        }
        // Insert outside of the async context; geocoding is triggered by the handler.
        Test.startTest();
        insert props;
        Test.stopTest();

        Assert.areEqual(
            GeocodingService.CHUNK_SIZE,
            [SELECT COUNT() FROM Property__c WHERE Location__Latitude__s != NULL],
            'First chunk geocoded; remaining chunk is chained outside tests'
        );
    }
}