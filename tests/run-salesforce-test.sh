#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${SF_BASE_URL:-https://velocity-speed-6495--dclouduat.sandbox.my.salesforce.com}"
TOKEN_URL="${BASE_URL}/services/oauth2/token"
CUSTOMERS_ENDPOINT="${BASE_URL}/services/apexrest/utc/v1/customers"
CLIENT_ID="${SF_CLIENT_ID:?Set SF_CLIENT_ID environment variable}"
CLIENT_SECRET="${SF_CLIENT_SECRET:?Set SF_CLIENT_SECRET environment variable}"

echo "=================================================================="
echo "1. Requesting OAuth2 Access Token (client_credentials)..."
echo "=================================================================="
TOKEN_RESPONSE=$(curl -sS -X POST "${TOKEN_URL}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Accept: application/json" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=${CLIENT_ID}" \
  --data-urlencode "client_secret=${CLIENT_SECRET}")

ACCESS_TOKEN=$(python3 -c 'import sys, json; data = json.loads(sys.stdin.read()); print(data.get("access_token", ""))' <<< "${TOKEN_RESPONSE}")

if [[ -z "${ACCESS_TOKEN}" ]]; then
  echo "Failed to acquire access_token. Response:"
  echo "${TOKEN_RESPONSE}"
  exit 1
fi

echo "Successfully acquired access token (prefix: ${ACCESS_TOKEN:0:18}...)"
echo ""

echo "=================================================================="
echo "2. Calling Health Check Endpoint (GET)..."
echo "=================================================================="
REQ_ID_HEALTH=$(uuidgen | tr '[:upper:]' '[:lower:]')
curl -i -sS -X GET "${CUSTOMERS_ENDPOINT}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "X-Request-Id: ${REQ_ID_HEALTH}" \
  -H "Accept: application/json"
echo -e "\n"

echo "=================================================================="
echo "3. Pushing Sample B2C Customer Payload (POST)..."
echo "=================================================================="
REQ_ID_POST=$(uuidgen | tr '[:upper:]' '[:lower:]')
curl -i -sS -X POST "${CUSTOMERS_ENDPOINT}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json; charset=utf-8" \
  -H "X-Request-Id: ${REQ_ID_POST}" \
  -H "Accept: application/json" \
  -d '{
  "customers": [
    {
      "dataAreaId": "utc",
      "CustomerAccount": "RC-081346",
      "PartyNumber": "000387281",
      "PartyType": "Person",
      "CustomerGroupId": "Retail",
      "PersonFirstName": "Abdullah",
      "PersonMiddleName": "",
      "PersonLastName": "Al-Rateeb",
      "NameAlias": "Abdullah Al-Rateeb",
      "PersonGender": "",
      "LanguageId": "en-US",
      "PrimaryContactPhone": "96550800075",
      "PrimaryContactPhoneIsMobile": "No",
      "PrimaryContactEmail": "",
      "AddressCity": "",
      "AddressCountryRegionId": "KWT",
      "OnHoldStatus": "No",
      "CreatedDateTimeCustTable": "2026-10-26T09:14:52Z",
      "ModifiedDateTimeCustTable": "2026-10-26T09:14:56Z",
      "SourceChannel": "POS",
      "OperatingUnitNumber": "D601",
      "Terminal": "D60102",
      "MarketingConsentSms": null,
      "MarketingConsentWhatsApp": null,
      "MarketingConsentEmail": null,
      "ConsentCapturedDateTime": null,
      "AliasCustomerAccounts": []
    }
  ]
}'
echo -e "\n"
