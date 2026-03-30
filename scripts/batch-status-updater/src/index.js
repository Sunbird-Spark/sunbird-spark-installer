const cassandra = require('cassandra-driver');
const axios = require('axios');
require('dotenv').config();

// Configuration from environment variables
const config = {
  yugabyte: {
    contactPoints: (process.env.YUGABYTE_HOST || 'localhost').split(','),
    port: parseInt(process.env.YUGABYTE_PORT || '9042'),
    username: process.env.YUGABYTE_USER || 'yugabyte',
    password: process.env.YUGABYTE_PASSWORD || 'yugabyte',
    keyspace: process.env.YUGABYTE_KEYSPACE || 'sunbird_courses',
    localDataCenter: process.env.YUGABYTE_DATACENTER || 'datacenter1',
  },
  elasticsearch: {
    host: process.env.ES_HOST || 'http://elasticsearch:9200',
  },
  timezone: process.env.TZ || 'Asia/Kolkata',
};

// Status constants
const STATUS = {
  NOT_STARTED: 0,
  IN_PROGRESS: 1,
  COMPLETED: 2,
};

// Status name mapping
function getStatusName(statusCode) {
  const statusMap = {
    0: 'Not Started',
    1: 'In Progress',
    2: 'Completed',
  };
  return statusMap[statusCode] || 'Unknown';
}

// Metrics tracking
let metrics = {
  beforeUpdate: { unStarted: 0, inProgress: 0, completed: 0 },
  afterUpdate: { unStarted: 0, inProgress: 0, completed: 0, changed: { toUnStarted: 0, toInProgress: 0, toCompleted: 0 } },
  timeTaken: 0,
};

/**
 * Get today's date in configured timezone as yyyy-MM-dd
 */
function getTodayInTimezone() {
  const now = new Date();
  const tzDate = new Date(now.toLocaleString('en-US', { timeZone: config.timezone }));
  return formatDate(tzDate.toISOString().split('T')[0]);
}

/**
 * Convert UTC datetime string to configured timezone date (yyyy-MM-dd)
 */
function convertDate(dateStr) {
  if (!dateStr) return null;
  try {
    let date = new Date(dateStr);
    if (isNaN(date.getTime())) {
      const parts = dateStr.split(/[' \-T:]/);
      if (parts.length >= 3) date = new Date(parts[0], parseInt(parts[1]) - 1, parts[2]);
    }
    const tzDate = new Date(date.toLocaleString('en-US', { timeZone: config.timezone }));
    const year = tzDate.getFullYear();
    const month = String(tzDate.getMonth() + 1).padStart(2, '0');
    const day = String(tzDate.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  } catch (error) {
    console.error(`Error converting date: ${dateStr}`, error.message);
    return null;
  }
}

/**
 * Format and validate date string to yyyy-MM-dd
 */
function formatDate(dateStr) {
  if (!dateStr) return null;
  try {
    const date = new Date(dateStr);
    if (isNaN(date.getTime())) {
      if (/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) return dateStr;
      return null;
    }
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  } catch (error) {
    console.error(`Error formatting date: ${dateStr}`, error.message);
    return null;
  }
}


/**
 * Normalize batch row dates from Cassandra/YugabyteDB
 */
function normalizeBatchDates(row) {
  return {
    courseid: row.courseid,
    batchid: row.batchid,
    startDate: convertDate(row.start_date),
    endDate: convertDate(row.end_date),
    enrollmentEndDate: convertDate(row.enrollment_enddate),
    enrollmentType: row.enrollmenttype,
    createdFor: row.createdfor || [],
    name: row.name,
    status: row.status,
  };
}

/**
 * Compute new status based on today's date and batch dates
 */
function computeNewStatus(todayInTZ, startDate, endDate) {
  // Must have start date to compute anything
  if (!startDate) return null;

  // If we have both dates, use full logic
  if (endDate) {
    if (todayInTZ > endDate) return STATUS.COMPLETED;
    if (todayInTZ >= startDate) return STATUS.IN_PROGRESS;
    return STATUS.NOT_STARTED;
  }

  // If only start_date exists (no end_date)
  // Mark as In Progress once it starts, never complete
  if (todayInTZ >= startDate) return STATUS.IN_PROGRESS;
  return STATUS.NOT_STARTED;
}

/**
 * Update batch status in YugabyteDB
 */
async function updateBatchStatusInCassandra(client, batches) {
  const query = `UPDATE ${config.yugabyte.keyspace}.course_batch SET status = ? WHERE courseid = ? AND batchid = ?`;

  console.log(`\nUpdating YugabyteDB (${config.yugabyte.keyspace}.course_batch)...`);
  console.log(`Total batches to update: ${batches.length}`);

  const promises = batches.map((batch, index) => {
    return client.execute(query, [batch.newStatus, batch.courseid, batch.batchid], { prepare: true })
      .then(() => {
        const statusName = getStatusName(batch.newStatus);
        console.log(`[${index + 1}/${batches.length}] Updated courseid=${batch.courseid}, batchid=${batch.batchid}, status=${batch.newStatus}(${statusName}), previous_status=${batch.status}(${getStatusName(batch.status)})`);
        return true;
      })
      .catch(error => {
        console.error(`ERROR: Failed to update courseid=${batch.courseid}, batchid=${batch.batchid}: ${error.message}`);
        throw error;
      });
  });

  await Promise.all(promises);
  console.log(`[SUCCESS] Updated ${batches.length} batches in YugabyteDB`);
}

/**
 * Update batch status in Elasticsearch
 */
async function updateBatchStatusInES(batches) {
  const esHost = config.elasticsearch.host;
  const batchesToUpdate = batches.filter(batch => batch.newStatus > 0);

  console.log(`\nUpdating Elasticsearch (host=${esHost}, index=course-batch)...`);
  console.log(`Total batches to update: ${batchesToUpdate.length} (filtered from ${batches.length} changed batches)`);
  console.log(`Note: Only updating batches with status > 0 (optimization)`);

  if (batchesToUpdate.length === 0) {
    console.log('[INFO] No batches to update in Elasticsearch (all statuses are 0)');
    return;
  }

  const promises = batchesToUpdate.map((batch, index) => {
    const url = `${esHost}/course-batch/_doc/${batch.batchid}/_update`;
    return axios.post(url, { doc: { status: batch.newStatus } })
      .then(() => {
        const statusName = getStatusName(batch.newStatus);
        console.log(`[${index + 1}/${batchesToUpdate.length}] Updated batchid=${batch.batchid}, status=${batch.newStatus}(${statusName}), previous_status=${batch.status}(${getStatusName(batch.status)})`);
        return true;
      })
      .catch(error => {
        console.warn(`[WARNING] Failed to update batchid=${batch.batchid} in Elasticsearch: ${error.response?.status || error.message}`);
        // Continue on Elasticsearch failures
        return false;
      });
  });

  const results = await Promise.allSettled(promises);
  const successCount = results.filter(r => r.status === 'fulfilled' && r.value).length;
  const failureCount = results.filter(r => r.status === 'rejected' || (r.status === 'fulfilled' && !r.value)).length;

  console.log(`[SUCCESS] Updated ${successCount}/${batchesToUpdate.length} batches in Elasticsearch`);
  if (failureCount > 0) {
    console.log(`[WARNING] Failed to update ${failureCount} batches in Elasticsearch (non-blocking failure)`);
  }
}

/**
 * Fetch all course batches from YugabyteDB
 */
async function fetchCourseBatches(client) {
  const fetchStartTime = Date.now();
  const query = `
    SELECT courseid, batchid, start_date, end_date, enrollment_enddate,
           enrollmenttype, createdfor, name, status
    FROM ${config.yugabyte.keyspace}.course_batch
  `;
  const result = await client.execute(query);
  const fetchTime = Date.now() - fetchStartTime;

  console.log(`[SUCCESS] Fetched ${result.rows.length} batches from YugabyteDB (${fetchTime}ms)`);

  // Normalize batches and log any data issues
  const normalizedBatches = result.rows.map((row, index) => {
    const normalized = normalizeBatchDates(row);

    // Validate critical fields
    if (!normalized.startDate && !normalized.endDate) {
      console.warn(`[WARNING] Batch ${index + 1}: courseid=${row.courseid}, batchid=${row.batchid} has no start_date or end_date`);
    } else if (!normalized.startDate) {
      console.warn(`[WARNING] Batch ${index + 1}: courseid=${row.courseid}, batchid=${row.batchid} has no start_date (only end_date=${normalized.endDate})`);
    }

    return normalized;
  });

  console.log(`[SUCCESS] Normalized ${normalizedBatches.length} batches`);
  return normalizedBatches;
}

/**
 * Update batch status - core logic
 */
async function updateBatchStatus(client, normalizedBatches) {
  const todayInTZ = getTodayInTimezone();
  console.log(`\nStatus Computation Configuration:`);
  console.log(`  Timezone: ${config.timezone}`);
  console.log(`  Today's date (${config.timezone}): ${todayInTZ}`);
  console.log(`  Total batches fetched: ${normalizedBatches.length}`);

  // Count initial status distribution
  normalizedBatches.forEach(batch => {
    if (batch.status === STATUS.NOT_STARTED) metrics.beforeUpdate.unStarted++;
    else if (batch.status === STATUS.IN_PROGRESS) metrics.beforeUpdate.inProgress++;
    else if (batch.status === STATUS.COMPLETED) metrics.beforeUpdate.completed++;
  });

  console.log(`\nStatus Distribution Before Update:`);
  console.log(`  Not Started: ${metrics.beforeUpdate.unStarted} batches`);
  console.log(`  In Progress: ${metrics.beforeUpdate.inProgress} batches`);
  console.log(`  Completed: ${metrics.beforeUpdate.completed} batches`);

  // Compute new status and filter changed batches
  console.log(`\nComputing new status for each batch...`);
  const allBatchesWithNewStatus = normalizedBatches
    .map(batch => ({ ...batch, newStatus: computeNewStatus(todayInTZ, batch.startDate, batch.endDate) }));

  const changedBatches = allBatchesWithNewStatus
    .filter(batch => batch.newStatus !== null && batch.newStatus !== batch.status);

  console.log(`Status computation completed. Total batches with status change: ${changedBatches.length}`);

  if (changedBatches.length === 0) {
    console.log(`[INFO] No batches changed status. All batches remain in their current state.`);
    return [];
  }

  // Count final status distribution
  allBatchesWithNewStatus.forEach(batch => {
    if (batch.newStatus === STATUS.NOT_STARTED) metrics.afterUpdate.unStarted++;
    else if (batch.newStatus === STATUS.IN_PROGRESS) metrics.afterUpdate.inProgress++;
    else if (batch.newStatus === STATUS.COMPLETED) metrics.afterUpdate.completed++;
  });

  changedBatches.forEach(batch => {
    if (batch.newStatus === STATUS.NOT_STARTED) metrics.afterUpdate.changed.toUnStarted++;
    else if (batch.newStatus === STATUS.IN_PROGRESS) metrics.afterUpdate.changed.toInProgress++;
    else if (batch.newStatus === STATUS.COMPLETED) metrics.afterUpdate.changed.toCompleted++;
  });

  console.log(`\nStatus Distribution After Update:`);
  console.log(`  Not Started: ${metrics.afterUpdate.unStarted} batches (${metrics.afterUpdate.changed.toUnStarted} changed to this status)`);
  console.log(`  In Progress: ${metrics.afterUpdate.inProgress} batches (${metrics.afterUpdate.changed.toInProgress} changed to this status)`);
  console.log(`  Completed: ${metrics.afterUpdate.completed} batches (${metrics.afterUpdate.changed.toCompleted} changed to this status)`);

  // Log detailed change summary
  console.log(`\nDetailed Summary of Changed Batches:`);
  const changesSummary = {
    toNotStarted: changedBatches.filter(b => b.newStatus === STATUS.NOT_STARTED),
    toInProgress: changedBatches.filter(b => b.newStatus === STATUS.IN_PROGRESS),
    toCompleted: changedBatches.filter(b => b.newStatus === STATUS.COMPLETED),
  };

  if (changesSummary.toNotStarted.length > 0) {
    console.log(`  Changed to Not Started: ${changesSummary.toNotStarted.length}`);
    changesSummary.toNotStarted.slice(0, 5).forEach((b, idx) => {
      console.log(`    [${idx + 1}] courseid=${b.courseid}, batchid=${b.batchid}, start=${b.startDate}, end=${b.endDate}`);
    });
    if (changesSummary.toNotStarted.length > 5) console.log(`    ... and ${changesSummary.toNotStarted.length - 5} more`);
  }

  if (changesSummary.toInProgress.length > 0) {
    console.log(`  Changed to In Progress: ${changesSummary.toInProgress.length}`);
    changesSummary.toInProgress.slice(0, 5).forEach((b, idx) => {
      console.log(`    [${idx + 1}] courseid=${b.courseid}, batchid=${b.batchid}, start=${b.startDate}, end=${b.endDate}`);
    });
    if (changesSummary.toInProgress.length > 5) console.log(`    ... and ${changesSummary.toInProgress.length - 5} more`);
  }

  if (changesSummary.toCompleted.length > 0) {
    console.log(`  Changed to Completed: ${changesSummary.toCompleted.length}`);
    changesSummary.toCompleted.slice(0, 5).forEach((b, idx) => {
      console.log(`    [${idx + 1}] courseid=${b.courseid}, batchid=${b.batchid}, start=${b.startDate}, end=${b.endDate}`);
    });
    if (changesSummary.toCompleted.length > 5) console.log(`    ... and ${changesSummary.toCompleted.length - 5} more`);
  }

  console.log(`\n${'='.repeat(80)}`);
  console.log(`STATUS UPDATE EXECUTION`);
  console.log(`${'='.repeat(80)}`);
  console.log(`Total batches to update: ${changedBatches.length}`);

  // Update YugabyteDB
  await updateBatchStatusInCassandra(client, changedBatches);

  // Update Elasticsearch
  try {
    await updateBatchStatusInES(changedBatches);
  } catch (error) {
    console.error(`[ERROR] Error updating Elasticsearch:`, error.message);
  }

  console.log(`${'='.repeat(80)}`);

  return changedBatches;
}

/**
 * Main execution function
 */
async function execute() {
  const startTime = Date.now();
  let client;

  try {
    console.log(`${'='.repeat(80)}`);
    console.log(`BATCH STATUS UPDATER JOB`);
    console.log(`Started: ${new Date().toISOString()}`);
    console.log(`${'='.repeat(80)}`);

    // Log configuration
    console.log(`\nConfiguration:`);
    console.log(`  Timezone: ${config.timezone}`);
    console.log(`  YugabyteDB Host(s): ${config.yugabyte.contactPoints.join(', ')}`);
    console.log(`  YugabyteDB Port: ${config.yugabyte.port}`);
    console.log(`  YugabyteDB Keyspace: ${config.yugabyte.keyspace}`);
    console.log(`  Elasticsearch Host: ${config.elasticsearch.host}`);

    // Connect to YugabyteDB
    console.log(`\nConnecting to YugabyteDB...`);
    const authProvider = new cassandra.auth.PlainTextAuthProvider(
      config.yugabyte.username,
      config.yugabyte.password
    );

    client = new cassandra.Client({
      contactPoints: config.yugabyte.contactPoints,
      port: config.yugabyte.port,
      localDataCenter: config.yugabyte.localDataCenter,
      authProvider: authProvider,
      keyspace: config.yugabyte.keyspace,
    });

    await client.connect();
    console.log(`[SUCCESS] Connected to YugabyteDB`);

    // Fetch all batches
    console.log(`\nFetching course batches from ${config.yugabyte.keyspace}.course_batch...`);
    const normalizedBatches = await fetchCourseBatches(client);

    // Update batch statuses
    await updateBatchStatus(client, normalizedBatches);

    // Calculate execution time
    metrics.timeTaken = Date.now() - startTime;

    // Log final metrics
    console.log(`\n${'='.repeat(80)}`);
    console.log(`JOB EXECUTION COMPLETED SUCCESSFULLY`);
    console.log(`${'='.repeat(80)}`);
    console.log(`\nExecution Summary:`);
    console.log(`  Total batches processed: ${normalizedBatches.length}`);
    console.log(`  Total batches changed: ${metrics.afterUpdate.changed.toUnStarted + metrics.afterUpdate.changed.toInProgress + metrics.afterUpdate.changed.toCompleted}`);
    console.log(`  Changed to Not Started: ${metrics.afterUpdate.changed.toUnStarted}`);
    console.log(`  Changed to In Progress: ${metrics.afterUpdate.changed.toInProgress}`);
    console.log(`  Changed to Completed: ${metrics.afterUpdate.changed.toCompleted}`);
    console.log(`  Total execution time: ${metrics.timeTaken}ms`);
    console.log(`  Average time per batch: ${(metrics.timeTaken / normalizedBatches.length).toFixed(2)}ms`);
    console.log(`  Job completed at: ${new Date().toISOString()}`);
    console.log(`${'='.repeat(80)}`);

  } catch (error) {
    const executionTime = Date.now() - startTime;
    console.error(`\n${'='.repeat(80)}`);
    console.error(`JOB EXECUTION FAILED`);
    console.error(`${'='.repeat(80)}`);
    console.error(`[ERROR] ${error.message}`);
    console.error(`Error occurred at: ${new Date().toISOString()}`);
    console.error(`Execution time before failure: ${executionTime}ms`);
    console.error(`Stack trace:`);
    console.error(error.stack);
    console.error(`${'='.repeat(80)}`);
    process.exit(1);
  } finally {
    if (client) {
      console.log(`\nClosing database connection...`);
      await client.shutdown();
      console.log(`[SUCCESS] Database connection closed`);
    }
  }
}

// Run the job
execute();
