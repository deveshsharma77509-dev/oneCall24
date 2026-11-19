# OneCall24 Salesforce Integration

## 1. Project Overview

The OneCall24 integration connects Salesforce with the OneCall24 external system using REST APIs.The main objective is to fetch candidate screening results from OneCall24, store them in Salesforce, and confirm successfully processed candidates back to OneCall24.
The integration also includes centralized exception handling, custom error logging, and an automated retry mechanism for failed API operations.

## 2. Business Requirement
The integration supports the following business operations:
1. Fetch candidate screening results from OneCall24.
2. Store candidate records in Salesforce.
3. Avoid duplicate records using External Reference as the External ID.
4. Confirm successfully processed candidates in OneCall24.
5. Reset candidate confirmations when required.
6. Maintain API failure and exception logs in Salesforce.
7. Automatically retry eligible failed operations.

## 3. Integration Architecture
**Salesforce → OneCall24 API**
**OneCall24 API → Salesforce**
The integration uses the following Apex classes:

| Apex Class | Responsibility |
|---|---|
| `OneCall24ApiService` | Main service class for fetching results, processing records, and resetting confirmations. |
| `OneCall24ApiClient` | Handles HTTP requests, Named Credential, headers, and timeout configuration. |
| `OneCall24Helper` | Handles JSON parsing, record preparation, error-log creation, bulk error logging, and log resolution. |
| `OneCall24ExceptionHandler` | Centralized exception handling for callout and other Apex exceptions. |
| `ConfirmCandidatesJob` | Queueable Apex class that confirms successfully processed candidate references asynchronously. |
| `OneCall24RetryScheduler` | it executes daily and invokes `OneCall24ApiService.fetchResults()` to fetch candidate records from the OneCall24 API |

## 4. Apex Class Explanation
### 4.1 OneCall24ApiClient
This class is responsible for communicating with the external OneCall24 API.
**Responsibilities:**
- Creates HTTP requests.
- Uses the `OneCall24_API` Named Credential.
- Sets HTTP methods and request headers.
- Applies timeout from Custom Metadata.
- Sends GET and POST requests.
- Returns the HTTP response to the calling service.

This class also reads API endpoint configurations from Custom Metadata instead of hardcoding endpoint paths.

### 4.2 OneCall24ApiService
This is the main service class that manages the integration business logic.
**Responsibilities:**
**Fetch Results**
- Calls the GET Results API.
- Receives candidate screening data.
- Parses the JSON response.
- Prepares Salesforce records.
- Upserts records into `Screening_Result__c`.
- Uses `External_Reference__c` to prevent duplicate records.
- Initiates the confirmation process for successfully processed candidates.

**Reset Confirmations**
- Calls the Reset API.
- Checks the HTTP response status.
- Logs successful API execution.
- Handles API failures through centralized exception/error handling.

### 4.3 OneCall24Helper
This class contains reusable helper methods to reduce duplicate code.
**Responsibilities:**
- Parses API JSON responses.
- Prepares candidate records for Salesforce.
- Creates error-log records.
- Saves error logs in bulk.
- Resolves related error logs after successful processing.

Error information is stored in: `OneCall24_Error_Log__c`

### 4.4 OneCall24ExceptionHandler
This class centralizes exception handling.
It provides separate methods for handling:
- Callout exceptions.
- Other Apex exceptions.

**Responsibilities:**
- Captures exception messages.
- Captures operation and endpoint details.
- Stores related candidate references.
- Sends exception information to the helper class for error-log creation.

This avoids writing the same exception logging logic in multiple Apex classes.

### 4.5 ConfirmCandidatesJob
This class implements:
- `Queueable`
- `Database.AllowsCallouts`

It confirms successfully processed candidate references in OneCall24.
**Execution flow:**
1. Receives candidate references from `OneCall24ApiService`.
2. Creates the confirmation API request.
3. Sends the candidate references to OneCall24.
4. Checks the API response.
5. Logs API failures or exceptions when required.

Queueable Apex allows confirmation processing to execute asynchronously after the Salesforce record-processing operation.

### 4.6 OneCall24RetryScheduler
This class implements Scheduled Apex and manages retry processing.
**Responsibilities:**
- Reads retry configuration from Custom Metadata.
- Checks whether retry is enabled.
- Finds eligible error logs.
- Updates retry count.
- Changes retry status to `Retrying`.
- Groups failed operations by operation type.
- Initiates the corresponding retry operation.
- Logs retry execution details.

The scheduler supports retry processing for:
- GET Results
- POST Confirm
- POST Reset
Maximum retry attempts and retryable HTTP status codes are configurable through Custom Metadata.

## 5. API Details
The integration uses three REST API endpoints.
| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/results?limit=200` | Fetch candidate screening results. |
| POST | `/confirm` | Mark successfully processed candidates as confirmed in OneCall24. |
| POST | `/reset` | Reset candidate confirmations in OneCall24. |

### GET Results API
Fetches candidate screening records from OneCall24.
Salesforce processes the response and stores the records in `Screening_Result__c`.

### POST Confirm API
After successful Salesforce processing, candidate references are sent to OneCall24.
OneCall24 marks the corresponding candidates as confirmed.

### POST Reset API
Resets confirmation status in OneCall24 when the reset operation is executed.

## 6. Salesforce Configuration
### Named Credential
**Name:** `OneCall24_API`
The Named Credential stores the external API connection details and authentication configuration.
The Apex code uses: `callout:OneCall24_API`

This avoids hardcoding the external API URL in Apex.

### Custom Metadata
**Custom Metadata Type:** `OneCall24_Settings__mdt`
**Record:** `Default`
| Field | Purpose |
| `Results_Path__c` | GET Results endpoint. |
| `Confirm_Path__c` | POST Confirm endpoint. |
| `Reset_Path__c` | POST Reset endpoint. |
| `Timeout__c` | HTTP request timeout in milliseconds. |
| `Retry_Enabled__c` | Enables or disables retry processing. |
| `Max_Retry__c` | Maximum retry attempts. |
| `Retryable_Status_Codes__c` | HTTP status codes eligible for retry. |

Current retryable status codes: `408, 429, 500, 502, 503, 504`

## 7. Salesforce Objects
### Screening_Result__c
Stores candidate screening results received from OneCall24.

**External ID:** `External_Reference__c`
The External ID supports upsert operations and helps prevent duplicate candidate records.

### OneCall24_Error_Log__c
Stores API failures and exception details.

Important fields:
| Field | Description |
| `Candidate_Reference__c` | Related candidate reference. |
| `API_Endpoint__c` | API endpoint where the failure occurred. |
| `Operation__c` | GET, Confirm, or Reset operation. |
| `HTTP_Status_Code__c` | HTTP response status code. |
| `Error_Type__c` | Type of error. |
| `Error_Message__c` | Error details. |
| `Response_Body__c` | API response body. |
| `Occurred_At__c` | Error occurrence date/time. |
| `Retry_Status__c` | Current retry status. |
| `Retry_Count__c` | Number of retry attempts. |

## 8. Retry Mechanism
The retry mechanism helps recover from temporary API failures.
**Execution flow:**
1. API operation fails.
2. Error details are stored in `OneCall24_Error_Log__c`.
3. Retry scheduler executes at its configured schedule.
4. Scheduler queries eligible error records.
5. Retry count is incremented.
6. Retry status changes to `Retrying`.
7. The appropriate API operation is initiated again.
8. Successful or failed execution is recorded in the error logs.

Retry behavior is controlled by Custom Metadata.

## 9. How to Execute
### Schedule Using Execute Anonymous
Open Salesforce Developer Console → Debug → Open Execute Anonymous Window.
Execute the following code:

```apex
System.schedule('OneCall24 Daily API Sync','0 0 13 * * ?',new OneCall24ScheduledJob());
```
Click **Execute**. Salesforce creates the scheduled job and returns a CronTrigger ID.
**Execution Method:** `OneCall24ApiService.fetchResults()`
**Result:** The `OneCall24ScheduledJob` executes daily at 1:00 PM IST and invokes `OneCall24ApiService.fetchResults()` to fetch candidate records from the OneCall24 API.

### Fetch Candidate Results without scheduler cron expression
Open Developer Console → Execute Anonymous:
```apex
OneCall24ApiService.fetchResults();
```
This executes the GET Results operation and processes the response.

### Confirm Candidates
Confirmation is initiated automatically after successful candidate processing through `ConfirmCandidatesJob`.

### Reset Confirmations
Execute Anonymous:
```apex
OneCall24ApiService.resetConfirmations();
```
This executes the POST Reset API.

### Execute Retry Scheduler Manually
```apex
OneCall24RetryScheduler scheduler = new OneCall24RetryScheduler();
scheduler.execute(null);
```

This manually executes the retry scheduler logic.

### Schedule Retry Scheduler
Go to: Setup → Scheduled Jobs → Schedule Apex.
Select `OneCall24RetryScheduler` and configure the required schedule.

## 10. Debugging and Monitoring
Use Salesforce Debug Logs to monitor integration execution.
Important log information includes:

- API endpoint and HTTP method.
- HTTP response status.
- API response body.
- Candidate processing.
- Queueable job execution.
- Exception messages.
- Retry count and retry status.

Example reset API debug messages:
```text
OneCall24 RESET API | HTTP Status: 200
OneCall24 RESET API executed successfully.
```

## 11. Error Handling
The integration handles two major types of errors:

**API/Callout Errors**
- HTTP error responses.
- Connection failures.
- Timeout exceptions.

**Apex Exceptions**
- JSON parsing exceptions.
- Record-processing exceptions.
- Other unexpected runtime exceptions.

Error information is centralized and stored in `OneCall24_Error_Log__c` for monitoring and retry processing.

## 12. Key Technical Features
- REST API integration.
- Named Credential authentication.
- Custom Metadata-based configuration.
- Bulk record upsert.
- External ID-based duplicate prevention.
- Queueable Apex for asynchronous processing.
- Scheduled Apex for retry processing.
- Centralized exception handling.
- Custom Salesforce error logging.
- Configurable timeout and retry settings.

## 13 Clone Repository & Setup
Other developers can clone the OneCall24 project using the following steps.
**Repository URL:**
https://github.com/deveshsharma77509-dev/oneCall24.git

### 1. Clone Repository
Open VS Code terminal and run:

```bash
git clone https://github.com/deveshsharma77509-dev/oneCall24.git
cd oneCall24
```

### 2. Switch to Feature Branch
```bash
git fetch origin
git switch --track origin/feature
```

### 3. Configure Git Identity
```bash
git config --global user.name "Developer Name"
git config --global user.email "developer@example.com"
```

### 4. Authorize Salesforce Org
- Open VS Code.
- Press `Ctrl + Shift + P`.
- Select `SFDX: Authorize an Org`.
- Complete Salesforce login.

### 5. Pull Latest Code
```bash
git pull origin feature
```

### 6. Push Developer Changes
```bash
git add .
git commit -m "Update OneCall24 integration"
git push origin feature
```

**Important:** Always work on the `feature` branch. The `main` branch is reserved for future stable releases. Developers need repository write access to push changes.

## 14. Conclusion

The OneCall24 integration provides an automated process to exchange candidate screening information between Salesforce and OneCall24.
It uses reusable Apex classes, Named Credentials, Custom Metadata, Queueable Apex, Scheduled Apex, centralized exception handling, and custom error logging to make the integration configurable, maintainable, and easier to monitor.