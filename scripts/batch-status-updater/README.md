# Batch Status Updater

CronJob that periodically updates course batch status based on start/end dates and syncs changes to YugabyteDB and Elasticsearch.

## Overview

This job:
1. Reads all course batches from YugabyteDB (Cassandra-compatible)
2. Normalizes date columns from UTC to configured timezone (yyyy-MM-dd format)
3. Computes new status based on today's date and batch start/end dates
4. Filters only batches where status changed
5. Updates YugabyteDB and Elasticsearch

## Status Values

| Value | Meaning | When (with end_date) | When (without end_date) |
|-------|---------|---|---|
| 0 | Not Started | Today is before batch start date | Today is before batch start date |
| 1 | In Progress | Today is on or after start date AND before end date | Today is on or after batch start date (never completes) |
| 2 | Completed | Today is after batch end date | Never (requires end_date) |

**Note:** Batches without an `end_date` will transition to "In Progress" when the `start_date` arrives but will never automatically transition to "Completed".

## Environment Variables

```bash
# YugabyteDB
YUGABYTE_HOST=localhost        # Comma-separated hosts
YUGABYTE_PORT=9042
YUGABYTE_USER=yugabyte
YUGABYTE_PASSWORD=yugabyte
YUGABYTE_KEYSPACE=sunbird_courses

# Elasticsearch
ES_HOST=http://localhost:9200

# Timezone (optional, defaults to Asia/Kolkata)
TZ=Asia/Kolkata                 # IANA timezone (e.g., America/New_York, Europe/London, etc.)
```

## Development

```bash
npm install
npm start
```

## Building Docker Image

```bash
docker build -t batch-status-updater:latest .
```

## Running in Docker

```bash
docker run --rm \
  -e YUGABYTE_HOST=yugabyte.default.svc.cluster.local \
  -e YUGABYTE_PORT=9042 \
  -e YUGABYTE_USER=yugabyte \
  -e YUGABYTE_PASSWORD=yugabyte \
  -e YUGABYTE_KEYSPACE=sunbird_courses \
  -e ES_HOST=http://elasticsearch:9200 \
  -e TZ=Asia/Kolkata \
  batch-status-updater:latest
```

## Key Functions

### getTodayInTimezone()
Returns today's date in configured timezone as yyyy-MM-dd

### convertDate(dateStr)
Converts UTC datetime string to configured timezone date (yyyy-MM-dd)
- Input: "2024-01-15 10:30:00" (UTC) or "2024-01-15T10:30:00Z" (ISO)
- Output: "2024-01-15" (in configured timezone)

### computeNewStatus(todayInTZ, startDate, endDate)
Core business logic that determines batch status:
- If today > endDate → Completed (2)
- If today >= startDate → In Progress (1)
- Else → Not Started (0)

## Data Flow

```
YugabyteDB (course_batch)
    ↓
Read & Normalize dates (UTC → Timezone)
    ↓
Compute new status
    ↓
Filter changed batches
    ↓
    ├─→ Update YugabyteDB
    └─→ Update Elasticsearch
```

## Metrics Logged

**Before Update:**
- Count of batches in each status

**After Update:**
- Count of batches in each status
- Count of batches changed to each status
- Total execution time (ms)

## Kubernetes Deployment

Deployed as a Kubernetes CronJob via Helm chart. See `helmcharts/learnbb/charts/lern/templates/cronjob-batch-status-updater.yaml` for configuration.

## Security

Never commit `.env` files with credentials. Use `.env.example` as a template.

## Example Output

```
Status Computation Configuration:
  Timezone: Asia/Kolkata
  Today's date (Asia/Kolkata): 2024-03-26
  Total batches fetched: 129

Updating YugabyteDB (sunbird_courses.course_batch)...
Total batches to update: 14
[1/14] Updated courseid=course1, batchid=batch1, status=1(In Progress), previous_status=0(Not Started)
[2/14] Updated courseid=course2, batchid=batch2, status=2(Completed), previous_status=1(In Progress)
...
[SUCCESS] Updated 14 batches in YugabyteDB

Updating Elasticsearch (host=http://elasticsearch:9200, index=course-batch)...
Total batches to update: 14 (filtered from 14 changed batches)
[1/14] Updated batchid=batch1, status=1(In Progress), previous_status=0(Not Started)
[2/14] Updated batchid=batch2, status=2(Completed), previous_status=1(In Progress)
...
[SUCCESS] Updated 14/14 batches in Elasticsearch

==================================================
Job completed successfully!
Total time taken: 408ms
==================================================
```

## Notes

- All dates are compared in the configured timezone (default: Asia/Kolkata)
- UTC timestamps are converted to the configured timezone before comparison
- Timezone is configurable via `TZ` environment variable
- Common timezone examples: `Asia/Kolkata`, `UTC`, `America/New_York`, `Europe/London`
- Only batches with status changes are synced to Elasticsearch
- YugabyteDB is Cassandra-compatible and uses CQL (Cassandra Query Language)
- Job logs status breakdown before and after updates
- Uses yyyy-MM-dd format for all date comparisons
- Elasticsearch updates only happen for batches with status > 0
