# UTC Dynamics 365 F&O to Salesforce Real-Time Customer Push Integration

Native Microsoft Dynamics 365 Finance & Operations (`X++` / Visual Studio 2022) real-time integration that detects B2C customer creation and updates in company `utc` and asynchronously pushes `CustomersV3`-aligned payloads to the Salesforce `DCloudUAT` Apex REST endpoint.

---

## Architecture Overview

1. **Change Detection Triggers (Chain of Command):**
   - `UTCSFCustTable_Extension` (`CustTable.insert()` and `CustTable.update()`)
   - `UTCSFDirPerson_Extension` & `UTCSFDirPersonName_Extension` (`DirPerson.update()`, `DirPersonName.insert()`, and `DirPersonName.update()` when `FirstName`, `MiddleName`, or `LastName` changes -> resolves linked `CustTable`)
   - `UTCSFLogisticsElectronicAddress_Extension` (`LogisticsElectronicAddress.insert()` and `LogisticsElectronicAddress.update()` when a primary phone or primary email changes -> resolves linked `CustTable` via `DirPartyLocation`)
2. **Pre-Flight Filtering (`UTCSFCustomerPushService.isEligibleCustomer`):**
   - `dataAreaId == "utc"`
   - `PartyType == "Person"` (skips `"Organization"`)
   - `CustomerGroupId` in `["Retail", "Cash", "B2C E-Comm"]`
   - At least one of `PersonFirstName` or `PersonLastName` is populated.
3. **Decoupled Staging Queue & Post-Commit Dispatch (`UTCSFCustomerPushQueue` & `UTCSFPostCommitDispatcher`):**
   - Enqueues eligible changes inside the database transaction without making blocking network calls.
   - Subscribes to `appl.onTtsNotifyCommit` to trigger `Global::runAsync` (`UTCSFCustomerPushBatchService::processQueueItemAsync`) immediately after the outer transaction commits, while `UTCSFCustomerPushBatchController` provides a recurring SysOperation batch job for resilient retry sweeps.
4. **OAuth2 Token Caching & HTTP Client (`UTCSFCustomerPushService`):**
   - Reads `TokenUrl`, `ApiEndpointUrl`, `ClientId`, and encrypted `ClientSecret` exclusively from `UTCSFIntegrationParameters` (no hardcoded credentials in X++).
   - Caches the OAuth2 `client_credentials` Bearer token in `UTCSFIntegrationParameters` for **120 minutes** (with a 5-minute safety buffer).
   - On `HTTP 401`, refreshes the cached token once and retries automatically.
   - Never retries `HTTP 400` (`Bad Request`).
   - Sends `Content-Type: application/json; charset=utf-8` (preserving Arabic characters) and `X-Request-Id: <unique-D365-GUID>`.
5. **Audit Logging (`UTCSFCustomerPushLog`):**
   - Logs every outbound call with `CustAccount`, `PartyNumber`, `RequestId`, `HttpStatus`, `SyncStatus`, `SalesforceAccountId`, `RequestPayload`, `ResponsePayload`, `DurationMs`, and `CreatedDateTime`.

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
