# Migration Manual Steps

Manual migration steps required by a release, documented here for reference. One section per release.

---

## Release 1.0.3 — Viewer Service DB Migration (YugabyteDB)

Rename the identity columns on **two** tables so the viewer can treat courses as generic collections:

| Table | Rename |
|-------|--------|
| `user_content_consumption` | `courseid → collectionid`, `batchid → contextid` |
| `assessment_aggregator` | `course_id → collection_id`, `batch_id → context_id` |

Renaming primary-key columns in YCQL is **metadata-only**: instant, no data copy, existing rows carry over.

Two parts: the table renames run in **YCQL** (`ycqlsh`, keyspace `sunbird_courses`); the report-definition
refresh (step 5) runs in **YSQL** (`ysqlsh`, database `sunbird`). They are separate clients on separate
ports, so you exit one before opening the other.

### 1. exec into the YugabyteDB pod (or SSH into the server)

Kubernetes:
```bash
kubectl exec -it <yugabyte-tserver-pod> -n sunbird -- bash
```
VM/server: just SSH in.

### 2. Open a YCQL shell
```bash
ycqlsh                      # connects to the local tserver on 9042
# add -u <user> -p <pass> if YCQL auth is enabled
```

### 3. Run the migration
```sql
USE sunbird_courses;

-- 1) user_content_consumption (no secondary index -> plain rename)
ALTER TABLE user_content_consumption RENAME courseid TO collectionid;
ALTER TABLE user_content_consumption RENAME batchid  TO contextid;

-- 2) assessment_aggregator (columns are used by an index -> drop, rename, recreate)
DROP INDEX IF EXISTS assessment_aggregator_by_user;

ALTER TABLE assessment_aggregator RENAME course_id TO collection_id;
ALTER TABLE assessment_aggregator RENAME batch_id  TO context_id;

CREATE INDEX IF NOT EXISTS assessment_aggregator_by_user
  ON assessment_aggregator (user_id, collection_id, context_id, content_id, attempt_id)
  INCLUDE (total_score, total_max_score, last_attempted_on)
  WITH CLUSTERING ORDER BY (collection_id ASC, context_id ASC, content_id ASC, attempt_id ASC)
  AND transactions = {'enabled': 'true'};
```

### 4. Verify
```sql
DESC TABLE sunbird_courses.user_content_consumption;   -- shows collectionid / contextid
DESC TABLE sunbird_courses.assessment_aggregator;      -- shows collection_id / context_id + index
```

### 5. Refresh observability report definitions (existing deployments only)

Two observability reports query `assessment_aggregator`, so their SQL must use the renamed
columns. Their definitions live in the **YSQL** table `standard_reports_meta`, in database
**`sunbird`** (seeded by the installer's `standard_reports_meta.sql`).

- **Fresh install:** nothing to do — the seed file already creates them with the new columns.
- **Existing install:** the rows already exist, and the seed's inserts are
  `ON CONFLICT (report_id) DO NOTHING` (re-running won't overwrite) — so update the two rows in place.

First **exit the YCQL shell** (`exit`, or Ctrl-D) to return to the pod shell — `ysqlsh` is a
different client on a different port (`5433`), you can't switch to it from inside `ycqlsh`. Then:
```bash
ysqlsh -d sunbird           # connects to the local tserver's YSQL on 5433
# add -h <host> -p 5433 -U <user> only if connecting from outside the pod
```
Update the two report queries (only the column names change; `WHERE` maps the unchanged
`courseid`/`batchid` filters onto the renamed columns):
```sql
UPDATE standard_reports_meta SET query_template =
'SELECT user_id, collection_id, context_id, content_id, attempt_id, total_score, total_max_score, last_attempted_on
  FROM sunbird_courses.assessment_aggregator
  WHERE collection_id = {{courseid}}
  {{#batchid}}AND context_id = {{batchid}}{{/batchid}}'
WHERE report_id = 'course-assessment-summary';

UPDATE standard_reports_meta SET query_template =
'SELECT collection_id, context_id, content_id, attempt_id, total_score, total_max_score, last_attempted_on
  FROM sunbird_courses.assessment_aggregator
  WHERE user_id = {{userid}}
  {{#courseid}}AND collection_id = {{courseid}}{{/courseid}}'
WHERE report_id = 'user-assessment-summary';
```

The request **filters stay `courseid` / `batchid`** — callers/UI payload is unchanged; the query
just maps them onto the renamed columns. Reports on `user_enrolments` are unaffected.

### Notes

- **Order matters** for `assessment_aggregator`: YCQL refuses to rename a column used in an index (`Feature Not Yet Implemented. Can't rename column used in an index`), so the index must be dropped **before** the rename and recreated **after**.
- The recreated index triggers an **async backfill** (table scan). On a large `assessment_aggregator`, run this off-peak.
- Statements are safe to re-run: `IF EXISTS` / `IF NOT EXISTS` guards on the index; a rename that's already applied will simply error on the old column name (harmless — the target state is already there).
- Keyspace is `sunbird_courses` by default; adjust if your `sunbird_course_keyspace` config points elsewhere.
