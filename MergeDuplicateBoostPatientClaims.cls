*************** Apex class of lwc ******************************

public class MergeDuplicateBoostPatientClaims {
    
    // AuraEnabled method to merge duplicate Boost Patient Claims
    @AuraEnabled
    public static void mergeBoostPatientClaims(List<Id> recordIds) {
        try {
            // Check if there are records to merge
            if (recordIds == null || recordIds.isEmpty()) {
                System.debug('No records to merge');
                return; // No records to merge
            }
            
            System.debug('Fetching Boost Patient Claims to merge');
            
            // Get all field names for the object type from schema
            Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Boost_Patient_Claim__c.fields.getMap();
            if (fieldMap.isEmpty()) {
                System.debug('No fields found for Boost_Patient_Claim__c');
                return;
            }
            
            // Get the list of editable fields
            List<String> editableFields = new List<String>();
            for (Schema.SObjectField field : fieldMap.values()) {
                if (field != null && field.getDescribe().isUpdateable()) {
                    editableFields.add(field.getDescribe().getName());
                }
            }
            
            // Query for Boost Patient Claims to be merged based on the provided record IDs
            String query = 'SELECT Id, ' + String.join(editableFields, ',') + ' FROM Boost_Patient_Claim__c WHERE Id IN :recordIds ORDER BY LastModifiedDate DESC';
            List<Boost_Patient_Claim__c> boostPatientClaimsToMerge = Database.query(query);
            
            // Map to group Boost Patient Claims by First_Name__c and Last_Name__c
            Map<String, List<Boost_Patient_Claim__c>> boostPatientClaimsByName = new Map<String, List<Boost_Patient_Claim__c>>();
            
            // Group Boost Patient Claims by First_Name__c and Last_Name__c
            if(!boostPatientClaimsToMerge.isEmpty()){
                for (Boost_Patient_Claim__c claims : boostPatientClaimsToMerge) {
                    if (claims.First_Name__c != null && claims.Last_Name__c != null) {
                        String fullName = claims.First_Name__c + ' ' + claims.Last_Name__c;
                        System.debug('Processing Boost Patient Claim with name: ' + fullName);
                        if (!boostPatientClaimsByName.containsKey(fullName)) {
                            boostPatientClaimsByName.put(fullName, new List<Boost_Patient_Claim__c>());
                        }
                        boostPatientClaimsByName.get(fullName).add(claims);
                    }
                }
            }
            
            // Iterate through grouped Boost Patient Claims and merge duplicates
            Map<Boost_Patient_Claim__c,Boost_Patient_Claim__c> dupToMaster = new Map<Boost_Patient_Claim__c,Boost_Patient_Claim__c>();
            if(!boostPatientClaimsByName.isEmpty()){
                for (String fullName : boostPatientClaimsByName.keySet()) {
                    List<Boost_Patient_Claim__c> dupes = boostPatientClaimsByName.get(fullName);
                    if (dupes != null && dupes.size() > 1) {
                        System.debug('Merging Boost Patient Claims with name: ' + fullName);
                        Boost_Patient_Claim__c master = dupes[0];
                        dupes.remove(0);
                        for(Boost_Patient_Claim__c claimDup: dupes){
                            dupToMaster.put(claimDup, master);
                        }
                    }
                }
                mergeBoostPatientClaims(dupToMaster, editableFields);
            }
        } catch (Exception e) {
            System.debug('An error occurred: ' + e.getMessage());
        }
    }
    
    // Private method to perform the merge of Boost Patient Claims
    private static void mergeBoostPatientClaims(Map<Boost_Patient_Claim__c,Boost_Patient_Claim__c> dupToMaster, List<String> editableFields) {
        try {
            
            //System.debug('Merging master Boost Patient Claim: ' + master.Id);
            Map<String, string> dupIdToMasterkey = new Map<String, string>();
            // Assign fields from duplicates to master
                for (Boost_Patient_Claim__c dupe : dupToMaster.keySet()) {
                    dupIdToMasterkey.put(dupe.Id, dupToMaster.get(dupe).id);
                    if (dupe == null) continue;
                    for (String fieldName : editableFields) {
                        // Check if the master record has a blank value at that field
                        if ( dupToMaster.get(dupe).get(fieldName) == null && dupe.get(fieldName) != null) {
                            // Assign the value from the duplicate record to the master record
                            dupToMaster.get(dupe).put(fieldName, dupe.get(fieldName));
                        }
                    }
                }
            Set<Boost_Patient_Claim__c> masterClaimsToUpdate = new Set<Boost_Patient_Claim__c>();
            masterClaimsToUpdate.addAll(dupToMaster.values());
             // Update the master Boost Patient Claim
             Database.update(new list<Boost_Patient_Claim__c>(masterClaimsToUpdate));
            
            // Re-parent the child records of the duplicate Boost Patient Claims to the master record
            List<Boost__c> childRecordsToUpdate = new List<Boost__c>();
            
            // Query for child records related to duplicates
            List<Boost__c> childRecords = [SELECT Id, Boost_Patient_Claim__c FROM Boost__c WHERE Boost_Patient_Claim__c IN :dupIdToMasterkey.keyset()];
            List<FeedItem> feedItems = [SELECT Id, ParentId, Body, Title, Type, Visibility, Status, HasContent, RelatedRecordId FROM FeedItem WHERE ParentId IN :dupIdToMasterkey.keyset() AND Type IN ('ContentPost', 'LinkPost', 'TextPost')];
            List<FeedComment> feedComments = [SELECT Id, FeedItemId, CommentBody, ParentId FROM FeedComment WHERE ParentId IN :dupIdToMasterkey.keyset()];
            
            // Update child records to point to the master record
            for (Boost__c childRecord : childRecords) {
                if (childRecord != null) {
                    childRecord.Boost_Patient_Claim__c = dupIdToMasterkey.get(childRecord.Boost_Patient_Claim__c);
                    childRecordsToUpdate.add(childRecord);
                }
            }
            
            // Create new FeedItem records with the same data but with the ParentId of the master record
            List<FeedItem> newFeedItems = new List<FeedItem>();
            for (FeedItem feedItem : feedItems) {
                if (feedItem != null) {
                    FeedItem newFeedItem = feedItem.clone(false, true, false, false);
                    newFeedItem.ParentId = dupIdToMasterkey.get(feedItem.ParentId);
                    newFeedItems.add(newFeedItem);
                }
            }
            Database.insert(newFeedItems); // Insert new FeedItems
            
            // Create a map to link old FeedItemId to new FeedItemId
            Map<Id, Id> feedItemIdMap = new Map<Id, Id>();
            for (Integer i = 0; i < feedItems.size(); i++) {
                if (feedItems[i] != null && newFeedItems[i] != null) {
                    feedItemIdMap.put(feedItems[i].Id, newFeedItems[i].Id); // Add to map
                }
            }
            
            // Create new FeedComment records with the same data but with the ParentId of the master record
            List<FeedComment> newFeedComments = new List<FeedComment>();
            for (FeedComment feedComment : feedComments) {
                if (feedComment != null) {
                    FeedComment newFeedComment = feedComment.clone(false, true, false, false);
                    newFeedComment.FeedItemId = feedItemIdMap.get(feedComment.FeedItemId); // Set FeedItemId using map
                    newFeedComments.add(newFeedComment);
                }
            }
                Database.insert(newFeedComments); // Insert new FeedComments
        
            // Update the child records
            if (!childRecordsToUpdate.isEmpty()) {
                Database.update(childRecordsToUpdate);
            }
            // Delete the duplicate Boost Patient Claims
            Database.delete(new list<Boost_Patient_Claim__c>(dupToMaster.keySet()));
        } catch (Exception e) {
            System.debug('An error occurred: ' + e.getMessage());
        }
    }
}

********************** Javascript file of lwc *******************************

// Import necessary modules from the Lightning Web Components and Salesforce platforms
import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

// Import Apex methods to be used in the component
import findDuplicateBoostPatientClaims from '@salesforce/apex/BoostPatientClaimController.findDuplicateBoostPatientClaims';
import mergeBoostPatientClaims from '@salesforce/apex/MergeDuplicateBoostPatientClaims.mergeBoostPatientClaims';

// Define columns for the data table
const columns = [
    { label: 'Name', fieldName: 'Name' },
    { label: 'First Name', fieldName: 'First_Name__c'},
    { label: 'Last Name', fieldName: 'Last_Name__c'},
    { label: 'Last Modified Date', fieldName: 'LastModifiedDate', type: 'date-local' },
];

// Export the LWC class as default
export default class DuplicateBoostPatientClaimFinder extends LightningElement {
    // Track changes to the first name and last name input fields
    @track firstNameValue = '';
    @track lastNameValue = '';

    // Track the list of duplicate patient claims and selected record IDs
    @track duplicateBoostPatientClaims = [];
    @track selectedIds = [];

    // Define the columns for the data table
    columns = columns;

    @wire(findDuplicateBoostPatientClaims, { firstName: '$firstNameValue', lastName: '$lastNameValue' })
    wiredRecords(result) {
        this.refreshTable = result;
        if ((this.firstNameValue || this.lastNameValue) && result.data) {
            this.duplicateBoostPatientClaims = result.data;
            console.log('result data'+ result.data);
        } else {
            this.duplicateBoostPatientClaims = [];
        }
    }

    // checkDuplicates(){ 
    //     console.log('firstname = '+this.firstNameValue);
    //     console.log('Lastname  = '+this.lastNameValue);
        
    //     findDuplicateBoostPatientClaims( { firstName: this.firstNameValue,  lastName: this.lastNameValue })
    //     .then((result)=>{
    //         if(result && result.data){
    //             this.duplicateBoostPatientClaims = result.data;
    //             if(this.duplicateBoostPatientClaims.length === 0){
    //                 throw new Error('No records found');
    //             }
    //         } else {
    //             throw new Error('No data returned from the server');
    //         }
    //     })
    //     .catch((error)=>{
    //         console.log(error);
    //         const toastEvent = new ShowToastEvent({
    //             title: 'Error',
    //             message: error.message,
    //             variant: 'error'
    //         });
    //         this.dispatchEvent(toastEvent);
    //     })
    // }

    // Handle changes in the first name and last name input fields
    handleFirstNameChange(event) {
        this.firstNameValue = event.target.value.trim() || null;
    }
    
    handleLastNameChange(event) {
        this.lastNameValue = event.target.value.trim() || null;
    }

    // Handle selection of rows in the data table
    handleRowSelection(event) {
        this.selectedIds = event.detail.selectedRows.map(row => row.Id);
    }

    // Merge selected records if more than one record is selected
    async mergeRecords() {
        if (this.selectedIds.length > 1) {
            try {
                // Call the Apex method to merge the selected records
                await mergeBoostPatientClaims({ recordIds: this.selectedIds });

                // Display a success toast message
                const successMessage = 'Records merged successfully.';
                const toastEvent = new ShowToastEvent({
                    title: 'Success',
                    message: successMessage,
                    variant: 'success'
                });
                this.dispatchEvent(toastEvent);

                // Reset selectedIds and duplicateBoostPatientClaims after merging
                this.selectedIds = [];
                this.duplicateBoostPatientClaims = [];

                // Refresh the data table
                return refreshApex(this.refreshTable);
            } catch (error) {
                // Log an error message if merging fails
                console.error('Error merging records:', error);
                const toastEvent = new ShowToastEvent({
                    title: 'Error',
                    message: error.message,
                    variant: 'error'
                });
                this.dispatchEvent(toastEvent);
            }
        }
    }
}
