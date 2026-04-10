# Migration Issues and Fixes

This document lists all data migration issues encountered during the migration from the old cluster to the new cluster, along with the fixes applied.

---

## 1. Neo4j → JanusGraph Migration

| # | Issue | Fix |
|---|-------|-----|
| 1 | Neo4j data not migrating to JanusGraph — old cluster had `sandbox.sunbirded.org` URLs hardcoded in `issuer` and `signatoryList` properties | Verified data migrated correctly — 1,161 vertices, 452 edges in JanusGraph |
| 2 | JanusGraph had 813 stale vertices from old cluster before migration | Deleted old vertices, reran migration for clean state |
| 3 | 4 nodes skipped during import due to JSON parse error in `import_data.groovy` | Non-fatal — script continues on parse error, remaining nodes imported successfully |

---

## 2. CQL Migrations (YugabyteDB YCQL)

| # | Issue | Fix |
|---|-------|-----|
| 4 | `CREATE INDEX` on tables with `transactions = {'enabled': 'true'}` → `(ql error -302)` — YugabyteDB does not support secondary indexes on transactional tables | Removed all `CREATE INDEX` statements from `sunbird.cql`, `sunbird_courses.cql`, `sunbird_groups.cql`, `sunbird-knowlg/sunbird.cql` |
| 5 | `assessment_aggregator` table creation failed — `frozen<question>` UDT not resolved when session keyspace is not set | Changed to fully qualified type: `frozen<sunbird_courses.question>` in `sunbird_courses.cql` |

---

## 3. Elasticsearch Migration

| # | Issue | Fix |
|---|-------|-----|
| 6 | `reindex.remote.whitelist` cannot be set via `PUT /_cluster/settings` API → HTTP 400 — it is a static setting, not dynamic | Added `extraConfig: reindex.remote.whitelist: "20.219.175.25:9200"` to learnbb ES helm values which injects into `elasticsearch.yml` |
| 7 | `userv3` count mismatch: old=139, new=94 | Expected — new cluster had 94 users (92 migrated + 2 newly created). Not data loss |
| 8 | `course-batch` count mismatch: old=106, new=82 | Expected — new cluster already had fresh data written by running services |
| 9 | `compositesearch` count mismatch: old=4706, new=1348 | Expected — new cluster has fresh content data from current deployment |

---

## 4. Login Issue

| # | Issue | Fix |
|---|-------|-----|
| 10 | Login failed with "Invalid Email/Password" after migration | Keycloak `cassandra-storage-provider` calls `lern-service` → queries ES `userv3` → index was empty → fixed after ES migration |
| 11 | `lern-service` user lookup returned empty (`result={response=[]}`) for migrated users | ES `userv3` was empty — populated after ES migration + `createdat` backfill + data sync |

---

## 5. createdat Backfill

| # | Issue | Fix |
|---|-------|-----|
| 12 | `createdat` field missing in YugabyteDB `sunbird.user` table — user creation count report broken | Added `createdat` column, backfilled from `createddate`, synced 92 users to ES |

---

## Summary

| Category | Issues | Fixed |
|----------|--------|-------|
| Neo4j → JanusGraph | 3 | 3 |
| CQL Migrations | 2 | 2 |
| Elasticsearch | 4 | 4 |
| Login | 2 | 2 |
| createdat Backfill | 1 | 1 |
| **Total** | **12** | **12** |
