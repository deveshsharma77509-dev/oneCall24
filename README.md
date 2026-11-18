# OneCall24 Salesforce Integration

## 1. Project Overview
This project integrates Salesforce with the OneCall24 REST API to fetch candidate screening results, store them in Salesforce, and confirm successfully processed candidates.

The integration also includes centralized error logging and an automated retry mechanism for API and record failures.

## 2. Business Purpose
- Automatically fetch candidate screening results from OneCall24.
- Store candidate information in Salesforce.
- Avoid duplicate records using External Reference ID.
- Confirm successfully processed candidates in OneCall24.
- Capture API failures, record failures, and exceptions.
- Automatically retry failed API requests and candidate records using `OneCall24RetryScheduler`.

## 3. Salesforce Components

### Custom Objects
- `Screening_Result__c` – Stores candidate screening information.
- `OneCall24_Error_Log__c` – Stores API errors, record failures, exception details, and retry status.

### Apex Classes
- `OneCall24ApiService` – Fetches API results, maps candidate data, upserts records, and handles errors.
- `ConfirmCandidatesJob` – Confirms successfully processed candidates through the OneCall24 API.
- `OneCall24RetryScheduler` – Schedules and processes retry operations for failed records and API requests.

## 4. API Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/results?limit=200` | Fetch candidate results |
| POST | `/confirm` | Confirm successfully processed candidates |
| POST | `/reset` | Reset confirmations for testing |

## 5. Authentication
Salesforce Named Credential: `OneCall24_API`

- External Credential manages API authentication.
- Custom Header sends the API key using `x-api-key`.
- API credentials are securely managed by Salesforce.

## 6. How to Execute

### Step 1: Fetch Candidate Results
Open Developer Console → Execute Anonymous and run:

```apex
OneCall24ApiService.fetchResults();
```

### Step 2: Verify Salesforce Records
Open the `Screening Results` tab and verify the fetched candidate records.

### Step 3: Verify Confirmation
Check Debug Logs and verify the `/confirm` API response.

### Step 4: Verify Error Logs
Open the `OneCall24 Error Logs` tab and check failed records, API errors, and retry statuses.

### Step 5: Execute Retry Scheduler

### Step 6: Check Scheduled Jobs
Go to Setup → Scheduled Jobs and verify the `OneCall24 Retry Scheduler` job.

## 7. Error Handling and Retry
- HTTP failures are captured in the error log object.
- Salesforce record failures are logged separately.
- Exceptions are captured with error messages and line numbers.
- Failed operations are retried by `OneCall24RetryScheduler`, according to its retry logic.
- Retry status helps track processing progress.

## 8. Technologies Used
- Salesforce Apex
- REST API Integration
- Named Credential
- External Credential
- Queueable Apex
- Scheduled Apex
- SOQL and DML
- Custom Error Logging

## 9. Conclusion
The integration automates candidate screening data synchronization between OneCall24 and Salesforce. It improves data consistency, reduces manual work, and provides centralized error tracking with automated retry handling.