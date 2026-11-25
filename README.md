# UTC Dynamics 365 F&O to Salesforce Real-Time Customer Push Integration

Native Microsoft Dynamics 365 Finance & Operations (`X++` / Visual Studio 2022) real-time integration that detects B2C customer creation and updates in company `utc` and asynchronously pushes `CustomersV3`-aligned payloads to the Salesforce `DCloudUAT` Apex REST endpoint.

---

## Architecture Overview (Salesforce Customer Push API v1.6)

1. **Change Detection Triggers (Events & Chain of Command):**
   - `UTCSFCustTable_Extension` (`CustTable` `Inserted` and `Updated` events — detects group changes including out-of-scope transitions like `Retail` -> `Coops`, on-hold status `Blocked`, and party/account changes)
   - `UTCSFDirPerson_Extension` & `UTCSFDirPersonName_Extension` (`DirPerson.update()`, `DirPersonName.insert()`, and `DirPersonName.update()` when `FirstName`, `MiddleName`, `LastName`, `Gender`, `LanguageId`, or primary phone/email pointers change -> resolves all linked `CustTable` accounts ordered main/oldest first)
   - `UTCSFLogisticsElectronicAddress_Extension` & `UTCSFLogisticsPostalAddress_Extension` (detects primary phone/email and primary postal city/country updates -> resolves linked `CustTable` via `DirPartyLocation`)
   - `UTCSFCustomerState` (`insert()` and `update()` when SMS, WhatsApp, or Email marketing consent changes -> auto-stamps `ConsentCapturedDateTime` in UTC and enqueues the customer)
2. **Pre-Flight Filtering (`UTCSFCustomerPushService.isEligibleCustomer`):**
   - `dataAreaId == "utc"`
   - `PartyType == "Person"` (skips `"Organization"`)
   - `CustomerGroupId` in configurable in-scope list: `["Retail", "B2C E-Comm", "Service", "Staff"]` (`Cash` excluded), **OR** an already-synced customer transitioning to an out-of-scope group (e.g., `"Coops"`) so Salesforce removes them from marketing audiences.
   - At least one of `PersonFirstName` or `PersonLastName` is populated.
3. **Decoupled Staging Queue, Async Coalescing & Batching (`UTCSFCustomerPushQueue`, `UTCSFPostCommitDispatcher`, `UTCSFCustomerPushBatchService`):**
   - Enqueues eligible changes inside the database transaction without making blocking network calls.
   - Subscribes to `appl.onTtsNotifyCommit` to trigger `Global::runAsync` (`UTCSFCustomerPushBatchService::processQueueItemAsync`) immediately after the outer transaction commits, coalescing rapid multi-datasource saves on the same customer to prevent Salesforce record locks.
   - `UTCSFCustomerPushBatchController` provides a recurring SysOperation batch job supporting chunked payloads of up to **200 customers per API call** (`BatchSizePerApiCall`).
4. **v1.6 Payload, OAuth2 Caching & Response Handling (`UTCSFCustomerPushService`):**
   - Computes composite `ModifiedDateTimeCustTable` across `CustTable`, GAB (`DirPersonName`, `LogisticsPostalAddress`), consent timestamps, and queue event time so GAB/consent updates always advance in UTC.
   - Populates `MarketingConsentSms`, `MarketingConsentWhatsApp`, `MarketingConsentEmail`, `ConsentCapturedDateTime`, and sibling `AliasCustomerAccounts`.
   - Handles Salesforce v1.6 row statuses: `created`, `updated`, `unchanged`, `skipped`, `matched`, `merged` (success + warning logging), `retry` (transient record lock -> retried by batch), and `error` (permanent validation failure -> never blind-retried).
5. **Companion Sync State & Audit Logging (`UTCSFCustomerState` & `UTCSFCustomerPushLog`):**
   - `UTCSFCustomerState` stores per-customer `SalesforceAccountId`, `SalesforcePersonContactId`, `IsSynced`, `LastSyncedCustGroup`, and marketing consent flags without locking `CustTable`.
   - `UTCSFCustomerPushLog` logs every outbound call with `CustAccount`, `PartyNumber`, `RequestId`, `HttpStatus`, `SyncStatus` (including `SucceededWithWarnings`), `RowStatus`, `MatchedOn`, `SalesforceAccountId`, `SalesforcePersonContactId`, `Warnings`, `RequestPayload`, `ResponsePayload`, and `DurationMs`.

---

## Repository Structure

```text
UTCCustomerPush/
├── UTCIntegration.sln
├── UTCIntegration/
│   └── UTCIntegration.rnrproj
├── Metadata/
│   └── UTCIntegration/
│       ├── Descriptor/
│       │   └── UTCIntegration.xml
│       └── UTCIntegration/
│           ├── AxEnum/
│           │   └── UTCSFCustomerPushStatus.xml
│           ├── AxEdt/
│           │   ├── UTCSFApiUrl.xml
│           │   ├── UTCSFClientId.xml
│           │   ├── UTCSFRequestId.xml
│           │   ├── UTCSFSalesforceAccountId.xml
│           │   └── UTCSFSourceChannel.xml
│           ├── AxTable/
│           │   ├── UTCSFIntegrationParameters.xml
│           │   ├── UTCSFCustomerPushQueue.xml
│           │   └── UTCSFCustomerPushLog.xml
│           ├── AxClass/
│           │   ├── UTCSFCustomerPushService.xml
│           │   ├── UTCSFCustomerPushBatchContract.xml
│           │   ├── UTCSFCustomerPushBatchService.xml
│           │   ├── UTCSFCustomerPushBatchController.xml
│           │   ├── UTCSFCustomerChangeHandler.xml
│           │   ├── UTCSFPostCommitDispatcher.xml
│           │   ├── UTCSFCustTable_Extension.xml
│           │   ├── UTCSFDirPerson_Extension.xml
│           │   ├── UTCSFDirPersonName_Extension.xml
│           │   └── UTCSFLogisticsElectronicAddress_Extension.xml
│           ├── AxForm/
│           │   ├── UTCSFIntegrationParameters.xml
│           │   ├── UTCSFCustomerPushLog.xml
│           │   └── UTCSFCustomerPushQueue.xml
│           ├── AxMenuItemDisplay/
│           │   ├── UTCSFIntegrationParameters.xml
│           │   ├── UTCSFCustomerPushLog.xml
│           │   └── UTCSFCustomerPushQueue.xml
│           ├── AxMenuItemAction/
│           │   └── UTCSFCustomerPushBatchController.xml
│           ├── AxMenuExtension/
│           │   └── AccountsReceivable.UTCIntegration.xml
│           ├── AxSecurityPrivilege/
│           │   ├── UTCSFIntegrationParametersMaintain.xml
│           │   └── UTCSFCustomerPushLogView.xml
│           └── AxSecurityDuty/
│               └── UTCSFCustomerIntegrationAdmin.xml
└── tests/
    └── salesforce-api.http
```

---

## Deployment & Configuration Steps

1. **Install Metadata into `PackagesLocalDirectory`:**
   Copy `Metadata/UTCIntegration` into `K:\AosService\PackagesLocalDirectory\UTCIntegration` on the D365 F&O Cloud Hosted Environment / Dev VM.
2. **Build & Synchronize Database:**
   Open `UTCIntegration.sln` in Visual Studio 2022, build the `UTCIntegration` model, and run a full Database Synchronization.
3. **Configure Parameters in D365 (`utc` legal entity):**
   Navigate to **Accounts receivable > Setup > Salesforce Integration Parameters** and enter:
   - **Enable Salesforce Push:** `Yes`
   - **OAuth2 Token URL:** `https://velocity-speed-6495--dclouduat.sandbox.my.salesforce.com/services/oauth2/token`
   - **Customer Push Endpoint URL:** `https://velocity-speed-6495--dclouduat.sandbox.my.salesforce.com/services/apexrest/utc/v1/customers`
   - **Client ID:** *(from Connected App)*
   - **Client Secret:** *(from Connected App — masked & encrypted)*
   - Click **Test Connection & Health Check** on the Action Pane to validate OAuth2 token acquisition and the `GET` health check endpoint.
4. **Schedule Fallback Retry Batch Job:**
   Navigate to **Accounts receivable > Periodic tasks > Process Salesforce Customer Push Queue** and schedule a recurring batch job (e.g., every 1–5 minutes) to sweep any transient network retries.
5. **Local REST Client Verification:**
   Open `tests/salesforce-api.http` in VS Code (with the REST Client extension) or Visual Studio 2022 and run requests `#1` (OAuth2 token), `#2` (Health Check `GET`), and `#3`/`#4` (Customer Push `POST`).
