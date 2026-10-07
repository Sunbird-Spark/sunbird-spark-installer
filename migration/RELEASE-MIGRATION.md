# Release Migration Guide

## 1. Standard Upgrade (Velero Backup + Restore)

Follow the steps below in order, for every release upgrade.

### Step 1 — Take a Database Backup

Take a full database backup before proceeding, as you would for any release, using Velero:

```
velero backup create manual-backup-$(date +%Y%m%d%H%M) --include-namespaces sunbird
```

Check status — should show `Completed`, not `PartiallyFailed`:

```
velero backup get
```

### Step 2 — Run the Installer

```
git clone https://github.com/Sunbird-Spark/sunbird-spark-installer.git
cd sunbird-spark-installer
git checkout spark-v1.1.0
git pull origin spark-v1.1.0
```

Follow the installer guide to complete infrastructure provisioning and service deployment.

### Step 3 — Carry Forward Existing Storage/Identity Values

**Do not let a new `global-cloud-values.yaml` get generated for the new environment.** Copy the **old** cluster's entire `global-cloud-values.yaml` file, as-is, into the new environment folder — this is what makes the storage get reused instead of new buckets being created.

1. Create the new environment folder as usual: `cp -r opentofu/<provider>/template opentofu/<provider>/<new-env-name>`
2. Copy the **old** cluster's `global-cloud-values.yaml` file into that new folder
3. Set `skip_storage_module: true` in the new environment's `global-values.yaml`.
4. From the **old** cluster's `global-values.yaml`, carry forward two separate sets of generated values into the new environment's `global-values.yaml`:
   - The 4 certificate keys — `CERTIFICATE_PRIVATE_KEY`, `CERTIFICATE_PUBLIC_KEY`, `CERTIFICATESIGN_PRIVATE_KEY`, `CERTIFICATESIGN_PUBLIC_KEY`. Idempotent: `certificate_keys()` checks for `CERTIFICATE_PRIVATE_KEY` already being present and skips regeneration if so.
   - The `default_passwords:` block (`grafana_admin_password`, `superset_admin_password`, `keycloak_password`) written by the `random_passwords` module. This one is **not** idempotent on its own — it regenerates on every apply — so it only stays correct because `deploy_tf_module random_passwords` is commented out in Step 4 below.

   See the root [README.md](../README.md) for the full field reference, and fill in any other required fields for a new environment that aren't part of this carry-forward.

### Step 4 — Bring Up the Infra (Private Cluster)

Before running, comment out these two lines inside `create_tf_resources()` in `install.sh`:
- `deploy_tf_module keys` — skips JWT/RSA key regeneration, so restored data stays valid against the old cluster's keys instead of getting signed against brand-new ones.
- `deploy_tf_module random_passwords` — skips regenerating grafana/superset/keycloak admin passwords, which would otherwise no longer match credentials baked into the restored data/configs.

Double-check the remaining modules (`network`, `storage`, `aks`, `workload-identity`, `output-file`, `upload-files`) are fine to run as normal for a fresh environment.

```
./install.sh create_tf_backend backup_configs create_tf_resources
```

### Step 5 — Access the New Cluster

Once the cluster is up, connect using whichever access method was configured for this environment — VPN (Pritunl) or Azure Bastion.

### Step 6 — Restore Data from Backup

```
velero restore create --from-backup manual-backup-<timestamp-from-step-1>
```

Check restore status — should show `Completed`, not `PartiallyFailed`, before proceeding:

```
velero restore get
```

Once confirmed, verify all services are running and try accessing the platform via its domain.

## 2. Release-Specific Migrations

Run these in addition to the standard upgrade above, if applicable to the release you're upgrading to. One section per release.

### Release 1.0.3 — Viewer Service DB Migration (YugabyteDB)

Rename the identity columns on **two** tables so the viewer can treat courses as generic collections:

| Table | Rename |
|-------|--------|
| `user_content_consumption` | `courseid → collectionid`, `batchid → contextid` |
| `assessment_aggregator` | `course_id → collection_id`, `batch_id → context_id` |

Renaming primary-key columns in YCQL is **metadata-only**: instant, no data copy, existing rows carry over.

Two parts: the table renames run in **YCQL** (`ycqlsh`, keyspace `sunbird_courses`); the report-definition
refresh (step 5) runs in **YSQL** (`ysqlsh`, database `sunbird`). They are separate clients on separate
ports, so you exit one before opening the other.

#### 1. exec into the YugabyteDB pod (or SSH into the server)

Kubernetes:
```bash
kubectl exec -it <yugabyte-tserver-pod> -n sunbird -- bash
```
VM/server: just SSH in.

#### 2. Open a YCQL shell
```bash
ycqlsh                      # connects to the local tserver on 9042
# add -u <user> -p <pass> if YCQL auth is enabled
```

#### 3. Run the migration
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

#### 4. Verify
```sql
DESC TABLE sunbird_courses.user_content_consumption;   -- shows collectionid / contextid
DESC TABLE sunbird_courses.assessment_aggregator;      -- shows collection_id / context_id + index
```

#### 5. Refresh observability report definitions (existing deployments only)

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

#### Notes

- **Order matters** for `assessment_aggregator`: YCQL refuses to rename a column used in an index (`Feature Not Yet Implemented. Can't rename column used in an index`), so the index must be dropped **before** the rename and recreated **after**.
- The recreated index triggers an **async backfill** (table scan). On a large `assessment_aggregator`, run this off-peak.
- Statements are safe to re-run: `IF EXISTS` / `IF NOT EXISTS` guards on the index; a rename that's already applied will simply error on the old column name (harmless — the target state is already there).
- Keyspace is `sunbird_courses` by default; adjust if your `sunbird_course_keyspace` config points elsewhere.

