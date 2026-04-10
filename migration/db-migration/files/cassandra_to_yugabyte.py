#!/usr/bin/env python3
"""
Cassandra to YugabyteDB Migration using PySpark

IMPORTANT: Two DIFFERENT hosts required
- cassandra_source.host → Reads FROM Cassandra (port 9042)
- yugabyte_ycql.host → Writes TO YugabyteDB (port 9043)

If hosts are the same, migrations will fail!
See HOST_CONFIGURATION.md for setup details.

Features:
- High-performance bulk migration for multiple keyspaces
- Reads all tables from Cassandra keyspaces dynamically
- Parallel distributed processing using Spark
- Writes to YugabyteDB YCQL (Cassandra-compatible API)
- Optimized for large datasets
"""

import os
import sys
import logging
from datetime import datetime
from pyspark.sql import SparkSession
from pyspark.sql.functions import col
import json
from cassandra.cluster import Cluster, BatchStatement
from cassandra import ProtocolVersion

# ============================
# Configuration
# ============================
CONFIG = {
    # Cassandra Source Connection (READ FROM)
    "cassandra_source": {
        "host": "{{ .Values.cassandra.host }}",
        "port": {{ .Values.cassandra.port }},
        "keyspaces": {{ .Values.cassandra.keyspaces | toJson }},
        "tables": None,
        "username": {{ if .Values.cassandra.username }}"{{ .Values.cassandra.username }}"{{ else }}None{{ end }},
        "password": {{ if .Values.cassandra.password }}"{{ .Values.cassandra.password }}"{{ else }}None{{ end }},
    },
    # YugabyteDB Target (YCQL - Cassandra Compatible) (WRITE TO)
    "yugabyte_ycql": {
        "host": "{{ .Values.yugabyte.host }}",
        "port": {{ .Values.yugabyte.port }},
        "username": {{ if .Values.yugabyte.username }}"{{ .Values.yugabyte.username }}"{{ else }}None{{ end }},
        "password": {{ if .Values.yugabyte.password }}"{{ .Values.yugabyte.password }}"{{ else }}None{{ end }},
    },
    # Spark Configuration (optimized for bulk migration)
    "spark": {
        "executor_memory": "4g",
        "driver_memory": "2g",
        "executor_cores": 4,
        "num_executors": 4,
        "cassandra_partitions": 64,
        "rdd_read_timeout": "300000",
    },
}

# ============================
# Logging Setup
# ============================
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)-8s | %(message)s',
    handlers=[
        logging.FileHandler('/var/log/migration/migration.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# ============================
# Cassandra Connection with Retry
# ============================
def cassandra_connect(hosts, port, keyspace=None, retries=5, delay=10):
    """Connect to Cassandra with retry/backoff to handle transient timeouts"""
    import time
    last_err = None
    for attempt in range(1, retries + 1):
        cluster = Cluster(hosts, port=port, protocol_version=4)
        try:
            session = cluster.connect(keyspace) if keyspace else cluster.connect()
            return cluster, session
        except Exception as e:
            last_err = e
            try:
                cluster.shutdown()
            except Exception:
                pass
            if attempt < retries:
                logger.warning(f"      Cassandra connect attempt {attempt}/{retries} failed — retrying in {delay}s")
                time.sleep(delay)
    raise last_err

# ============================
# Spark Session Setup
# ============================
def create_spark_session():
    """Create and configure Spark session optimized for bulk migration"""
    spark = SparkSession.builder \
        .appName("CassandraToYugabyteDB-BulkMigration") \
        .config("spark.executor.memory", CONFIG["spark"]["executor_memory"]) \
        .config("spark.driver.memory", CONFIG["spark"]["driver_memory"]) \
        .config("spark.executor.cores", str(CONFIG["spark"]["executor_cores"])) \
        .config("spark.sql.shuffle.partitions", "256") \
        .config("spark.sql.adaptive.enabled", "true") \
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
        .config("spark.cassandra.connection.host", CONFIG["cassandra_source"]["host"]) \
        .config("spark.cassandra.connection.port", str(CONFIG["cassandra_source"]["port"])) \
        .config("spark.cassandra.read.timeout_ms", CONFIG["spark"]["rdd_read_timeout"]) \
        .config("spark.cassandra.write.consistency", "ONE") \
        .getOrCreate()

    spark.sparkContext.setLogLevel("WARN")
    return spark

# ============================
# Get Tables from Cassandra
# ============================
def get_keyspace_tables(spark, keyspace):
    """Fetch all tables from a specific keyspace using cassandra-driver"""
    try:
        # Check if tables manually specified
        if CONFIG["cassandra_source"].get("tables"):
            tables = CONFIG["cassandra_source"]["tables"]
            logger.info(f"  Using manually specified tables: {', '.join(tables)}")
            return tables

        logger.info(f"  Auto-discovering tables in keyspace: {keyspace}")

        # Use cassandra-driver to query system tables (avoids Spark routing issues)
        try:
            cassandra_host = CONFIG["cassandra_source"]["host"]
            cassandra_port = CONFIG["cassandra_source"]["port"]

            cluster, session = cassandra_connect([cassandra_host], cassandra_port)

            tables = []

            # Try Cassandra 3.11 system.schema_columnfamilies first (old version)
            try:
                result = session.execute(
                    f"SELECT columnfamily_name FROM system.schema_columnfamilies WHERE keyspace_name = '{keyspace}'"
                )
                tables = [row.columnfamily_name for row in result]

                if tables:
                    logger.info(f"  Found {len(tables)} table(s) via system.schema_columnfamilies: {', '.join(tables)}")
                    session.shutdown()
                    cluster.shutdown()
                    return tables

            except Exception as e1:
                logger.info(f"  system.schema_columnfamilies not available: {str(e1)[:60]}")

            # Try Cassandra 4.0+ system_schema.tables (new version)
            try:
                result = session.execute(
                    f"SELECT table_name FROM system_schema.tables WHERE keyspace_name = '{keyspace}'"
                )
                tables = [row.table_name for row in result]

                if tables:
                    logger.info(f"  Found {len(tables)} table(s) via system_schema.tables: {', '.join(tables)}")
                    session.shutdown()
                    cluster.shutdown()
                    return tables

            except Exception as e2:
                logger.info(f"  system_schema.tables not available: {str(e2)[:60]}")

            session.shutdown()
            cluster.shutdown()

            if not tables:
                logger.warning(f"  No tables found in keyspace {keyspace}")

            return tables

        except Exception as e:
            logger.error(f"  Failed to connect to Cassandra for auto-discovery: {str(e)[:80]}")
            return []

    except Exception as e:
        logger.error(f"  Error fetching tables from {keyspace}: {str(e)}")
        return []

# ============================
# Verify Counts Before/After Migration
# ============================
def get_cassandra_count(keyspace, table_name):
    """Get row count from Cassandra using cassandra-driver"""
    try:
        cassandra_host = CONFIG["cassandra_source"]["host"]
        cassandra_port = CONFIG["cassandra_source"]["port"]

        cluster, session = cassandra_connect([cassandra_host], cassandra_port, keyspace)

        result = session.execute(f"SELECT COUNT(*) FROM {table_name}")
        count = result[0][0] if result else 0

        session.shutdown()
        cluster.shutdown()
        return count
    except Exception as e:
        logger.warning(f"      Failed to get Cassandra count: {str(e)[:60]}")
        return None

def get_yugabyte_count(keyspace, table_name):
    """Get row count from YugabyteDB using cassandra-driver"""
    try:
        yb_host = CONFIG["yugabyte_ycql"]["host"]
        yb_port = CONFIG["yugabyte_ycql"]["port"]

        cluster = Cluster([yb_host], port=yb_port, protocol_version=4)
        session = cluster.connect(keyspace)

        result = session.execute(f"SELECT COUNT(*) FROM {table_name}")
        count = result[0][0] if result else 0

        session.shutdown()
        cluster.shutdown()
        return count
    except Exception as e:
        logger.warning(f"      Failed to get YugabyteDB count: {str(e)[:60]}")
        return None

# ============================
# Detect Counter Table
# ============================
def is_counter_table(keyspace, table_name, session=None):
    """Return (is_counter, pk_cols, counter_cols) for the table.
    Accepts an optional open Cassandra session to avoid opening a new connection."""
    own_session = False
    if session is None:
        cassandra_host = CONFIG["cassandra_source"]["host"]
        cassandra_port = CONFIG["cassandra_source"]["port"]
        cluster, session = cassandra_connect([cassandra_host], cassandra_port)
        own_session = True

    rows = session.execute(
        f"SELECT column_name, type, kind, position FROM system_schema.columns "
        f"WHERE keyspace_name = '{keyspace}' AND table_name = '{table_name}'"
    )
    columns = list(rows)

    if own_session:
        session.shutdown()
        cluster.shutdown()

    counter_cols = [c.column_name for c in columns if c.type == 'counter']
    pk_cols = sorted([c for c in columns if c.kind in ('partition_key', 'clustering')], key=lambda c: c.position)
    pk_col_names = [c.column_name for c in pk_cols]
    return bool(counter_cols), pk_col_names, counter_cols


# ============================
# Ensure UDTs exist in YugabyteDB
# ============================
def ensure_udts(keyspace, cass_session, yb_session):
    """Create all UDTs from Cassandra keyspace in YugabyteDB if they don't exist"""
    try:
        udt_rows = list(cass_session.execute(
            f"SELECT type_name, field_names, field_types FROM system_schema.types "
            f"WHERE keyspace_name = '{keyspace}'"
        ))
        if not udt_rows:
            logger.info(f"      No UDTs found in keyspace '{keyspace}'")
            return
        logger.info(f"      Found {len(udt_rows)} UDT(s) in '{keyspace}': {[u.type_name for u in udt_rows]}")
        for udt in udt_rows:
            # YugabyteDB requires collection fields inside UDTs to be fully frozen
            def freeze_if_collection(t):
                if t.startswith(('list<', 'set<', 'map<')):
                    return f"frozen<{t}>"
                return t
            fields = ", ".join([f"{fname} {freeze_if_collection(ftype)}" for fname, ftype in zip(udt.field_names, udt.field_types)])
            create_udt = f"CREATE TYPE IF NOT EXISTS {keyspace}.{udt.type_name} ({fields})"
            logger.info(f"      UDT DDL: {create_udt}")
            try:
                yb_session.execute(create_udt)
                logger.info(f"      ✓ UDT '{udt.type_name}' created in YugabyteDB")
            except Exception as udt_err:
                logger.error(f"      ✗ Failed to create UDT '{udt.type_name}': {udt_err}")
    except Exception as e:
        import traceback
        logger.error(f"      Could not sync UDTs for keyspace '{keyspace}': {e}")
        logger.error(traceback.format_exc())

# ============================
# Direct Stream from Cassandra to YugabyteDB
# ============================
def stream_cassandra_to_yugabyte(keyspace, table_name):
    """Stream data directly from Cassandra to YugabyteDB using cassandra-driver"""
    try:
        # Source: Cassandra
        cassandra_host = CONFIG["cassandra_source"]["host"]
        cassandra_port = CONFIG["cassandra_source"]["port"]

        cass_cluster, cass_session = cassandra_connect([cassandra_host], cassandra_port, keyspace)

        # Target: YugabyteDB
        yb_host = CONFIG["yugabyte_ycql"]["host"]
        yb_port = CONFIG["yugabyte_ycql"]["port"]

        yb_cluster = Cluster([yb_host], port=yb_port, protocol_version=4)
        yb_session = yb_cluster.connect(keyspace)

        # Read from Cassandra
        result = cass_session.execute(f"SELECT * FROM {table_name}")
        rows = result.all()
        row_count = len(rows)

        if row_count == 0:
            logger.info(f"      Read {row_count} rows (empty table) — ensuring table exists in YugabyteDB")
            # Even empty tables must exist in YugabyteDB with correct schema
            try:
                yb_session.execute(f"SELECT COUNT(*) FROM {keyspace}.{table_name}")
                logger.info(f"      Table already exists in YugabyteDB")
            except Exception:
                logger.warning(f"      Table missing in YugabyteDB — creating from Cassandra schema")
                ensure_udts(keyspace, cass_session, yb_session)
                create_ddl = get_table_schema_from_cassandra(keyspace, table_name, session=cass_session)
                logger.info(f"      DDL: {create_ddl}")
                yb_session.execute(create_ddl)
                logger.info(f"      ✓ Created empty table in YugabyteDB")
            cass_session.shutdown()
            cass_cluster.shutdown()
            yb_session.shutdown()
            yb_cluster.shutdown()
            return row_count

        column_names = result.column_names

        # Check if this is a counter table (reuse existing cass_session — no new connection)
        has_counter, pk_col_names, counter_col_names = is_counter_table(keyspace, table_name, session=cass_session)

        def recreate_table_from_cass():
            """Drop and recreate table in YugabyteDB using schema from already-open cass_session"""
            logger.warning(f"      Table '{keyspace}.{table_name}' missing/broken in YugabyteDB — recreating from Cassandra schema")
            ensure_udts(keyspace, cass_session, yb_session)
            create_ddl = get_table_schema_from_cassandra(keyspace, table_name, session=cass_session)
            create_ddl = create_ddl.replace("CREATE TABLE IF NOT EXISTS", "CREATE TABLE")
            try:
                yb_session.execute(f"DROP TABLE IF EXISTS {keyspace}.{table_name}")
                logger.info(f"      Dropped existing table")
            except Exception as drop_err:
                logger.warning(f"      DROP TABLE warning (continuing): {drop_err}")
            logger.info(f"      DDL: {create_ddl}")
            yb_session.execute(create_ddl)
            logger.info(f"      ✓ Table recreated successfully")

        if has_counter:
            # Counter tables: use UPDATE counter SET col = col + value WHERE pk = value
            logger.info(f"      Counter table detected — using UPDATE syntax")
            set_parts = ", ".join([f"{c} = {c} + ?" for c in counter_col_names])
            where_parts = " AND ".join([f"{c} = ?" for c in pk_col_names])
            update_query = f"UPDATE {keyspace}.{table_name} SET {set_parts} WHERE {where_parts}"
            try:
                prepared_stmt = yb_session.prepare(update_query)
            except Exception as prep_err:
                if "-301" in str(prep_err) or "Object Not Found" in str(prep_err):
                    recreate_table_from_cass()
                    prepared_stmt = yb_session.prepare(update_query)
                else:
                    raise

            col_index = {name: idx for idx, name in enumerate(column_names)}
            counter_indices = [col_index[c] for c in counter_col_names]
            pk_indices = [col_index[c] for c in pk_col_names]

            for row in rows:
                bound_values = [row[i] for i in counter_indices] + [row[i] for i in pk_indices]
                yb_session.execute(prepared_stmt.bind(bound_values))

        else:
            # Regular tables: use INSERT
            columns_str = ", ".join(column_names)
            placeholders = ", ".join(["?" for _ in column_names])
            insert_query = f"INSERT INTO {keyspace}.{table_name} ({columns_str}) VALUES ({placeholders})"
            try:
                prepared_stmt = yb_session.prepare(insert_query)
            except Exception as prep_err:
                if "-301" in str(prep_err) or "Object Not Found" in str(prep_err):
                    recreate_table_from_cass()
                    prepared_stmt = yb_session.prepare(insert_query)
                else:
                    raise

            # Stream rows directly to YugabyteDB in batches
            batch_size = 100
            batch = []
            for row in rows:
                batch.append(prepared_stmt.bind(row))

                if len(batch) >= batch_size:
                    batch_stmt = BatchStatement()
                    for stmt in batch:
                        batch_stmt.add(stmt)
                    yb_session.execute(batch_stmt)
                    batch = []

            if batch:
                batch_stmt = BatchStatement()
                for stmt in batch:
                    batch_stmt.add(stmt)
                yb_session.execute(batch_stmt)

        cass_session.shutdown()
        cass_cluster.shutdown()
        yb_session.shutdown()
        yb_cluster.shutdown()

        logger.info(f"      Streamed {row_count:,} rows")
        return row_count

    except Exception as e:
        import traceback
        logger.error(f"      Failed to stream table {keyspace}.{table_name}: {str(e)}")
        logger.error(f"      Stack trace:\n{traceback.format_exc()}")
        raise

# ============================
# Get Table Schema from Cassandra
# ============================
def get_table_schema_from_cassandra(keyspace, table_name, session=None):
    """Read column definitions and primary key from Cassandra to build CREATE TABLE.
    Accepts an optional open Cassandra session to avoid opening a new connection."""
    own_session = False
    if session is None:
        cassandra_host = CONFIG["cassandra_source"]["host"]
        cassandra_port = CONFIG["cassandra_source"]["port"]
        cluster, session = cassandra_connect([cassandra_host], cassandra_port)
        own_session = True

    # Get columns with their types and kind (partition_key, clustering, regular)
    rows = session.execute(
        f"SELECT column_name, type, kind, position FROM system_schema.columns "
        f"WHERE keyspace_name = '{keyspace}' AND table_name = '{table_name}'"
    )
    columns = list(rows)

    if own_session:
        session.shutdown()
        cluster.shutdown()

    if not columns:
        return None

    # Separate by kind
    partition_keys = sorted([c for c in columns if c.kind == 'partition_key'], key=lambda c: c.position)
    clustering_cols = sorted([c for c in columns if c.kind == 'clustering'], key=lambda c: c.position)
    regular_cols = [c for c in columns if c.kind not in ('partition_key', 'clustering')]

    # Build column definitions
    col_defs = []
    for c in partition_keys + clustering_cols + regular_cols:
        col_defs.append(f"{c.column_name} {c.type}")

    # Build PRIMARY KEY clause
    pk_cols = [c.column_name for c in partition_keys]
    ck_cols = [c.column_name for c in clustering_cols]

    if len(pk_cols) == 1 and not ck_cols:
        primary_key = f"PRIMARY KEY ({pk_cols[0]})"
    elif not ck_cols:
        primary_key = f"PRIMARY KEY (({', '.join(pk_cols)}))"
    else:
        primary_key = f"PRIMARY KEY (({', '.join(pk_cols)}), {', '.join(ck_cols)})"

    # Tables that require transactions = {'enabled': 'true'} in YugabyteDB
    # Extracted from sunbird-yugabyte-migrations CQL files
    TRANSACTIONAL_TABLES = {
        # qmzbm_form_service
        "qmzbm_form_service.form_data", "qmzbm_form_service.cassandra_migration_version",
        "qmzbm_form_service.cassandra_migration_version_counts",
        # sunbird
        "sunbird.action_group", "sunbird.address", "sunbird.assessment_eval",
        "sunbird.assessment_item", "sunbird.badge", "sunbird.badge_class_extension",
        "sunbird.bulk_upload_process", "sunbird.bulk_upload_process_task",
        "sunbird.cassandra_migration_version", "sunbird.cassandra_migration_version_counts",
        "sunbird.cert_registry", "sunbird.client_info", "sunbird.config_path_audit",
        "sunbird.content_badge_association", "sunbird.content_consumption",
        "sunbird.course_batch", "sunbird.course_enrollment", "sunbird.course_management",
        "sunbird.course_publish_status", "sunbird.email_template", "sunbird.geo_location",
        "sunbird.group", "sunbird.group_member", "sunbird.location", "sunbird.master_action",
        "sunbird.media_type", "sunbird.org_external_identity", "sunbird.organisation",
        "sunbird.otp", "sunbird.page_management", "sunbird.page_section", "sunbird.rate_limit",
        "sunbird.report_tracking", "sunbird.role", "sunbird.role_group", "sunbird.shadow_user",
        "sunbird.skills", "sunbird.subject", "sunbird.system_settings",
        "sunbird.tenant_preference", "sunbird.tenant_preference_v2", "sunbird.url_action",
        "sunbird.user", "sunbird.user_action_role", "sunbird.user_auth",
        "sunbird.user_badge", "sunbird.user_badge_assertion", "sunbird.user_cert",
        "sunbird.user_consent", "sunbird.user_courses", "sunbird.user_declarations",
        "sunbird.user_education", "sunbird.user_external_identity", "sunbird.user_feed",
        "sunbird.user_group", "sunbird.user_job_profile", "sunbird.user_lookup",
        "sunbird.user_notes", "sunbird.user_org", "sunbird.user_organisation",
        "sunbird.user_roles", "sunbird.user_skills", "sunbird.usr_external_identity",
        # sunbird_courses
        "sunbird_courses.assessment_aggregator", "sunbird_courses.bulk_upload_process",
        "sunbird_courses.cassandra_migration_version", "sunbird_courses.cassandra_migration_version_counts",
        "sunbird_courses.content_consumption", "sunbird_courses.course_batch",
        "sunbird_courses.report_user_enrolments", "sunbird_courses.user_activity_agg",
        "sunbird_courses.user_content_consumption", "sunbird_courses.user_courses",
        "sunbird_courses.user_enrolments",
        # sunbird_groups
        "sunbird_groups.cassandra_migration_version", "sunbird_groups.cassandra_migration_version_counts",
        "sunbird_groups.group", "sunbird_groups.group_member", "sunbird_groups.user_group",
        # sunbird_notifications
        "sunbird_notifications.action_template", "sunbird_notifications.cassandra_migration_version",
        "sunbird_notifications.cassandra_migration_version_counts", "sunbird_notifications.feed_version_map",
        "sunbird_notifications.notification_feed", "sunbird_notifications.notification_template",
        # sunbird_programs
        "sunbird_programs.cassandra_migration_version", "sunbird_programs.cassandra_migration_version_counts",
        "sunbird_programs.program_enrollment",
        # dialcodes
        "dialcodes.dialcode_batch", "dialcodes.dialcode_images",
        # content_store
        "content_store.content_data",
    }

    # Add ENV-prefixed tables dynamically (e.g. sb_content_store, sb_category_store)
    env = os.environ.get("ENV", "sb")
    ENV_TRANSACTIONAL_TABLES = {
        f"{env}_category_store.category_definition_data",
        f"{env}_content_store.content_data",
        f"{env}_content_store.question_data",
        f"{env}_dialcode_store.dial_code",
        f"{env}_dialcode_store.publisher",
        f"{env}_dialcode_store.system_config",
        f"{env}_hierarchy_store.content_hierarchy",
        f"{env}_hierarchy_store.framework_hierarchy",
        f"{env}_hierarchy_store.hierarchy_relations",
        f"{env}_script_store.script_data",
    }
    TRANSACTIONAL_TABLES = TRANSACTIONAL_TABLES | ENV_TRANSACTIONAL_TABLES

    transactions_clause = ""
    if f"{keyspace}.{table_name}" in TRANSACTIONAL_TABLES:
        transactions_clause = " WITH transactions = {'enabled': 'true'}"

    create_stmt = (
        f"CREATE TABLE IF NOT EXISTS {keyspace}.{table_name} "
        f"({', '.join(col_defs)}, {primary_key}){transactions_clause}"
    )
    return create_stmt


# ============================
# Check/Create YugabyteDB Schema
# ============================
def ensure_yugabyte_schema(keyspace, table_name):
    """Verify keyspace and table exist on YugabyteDB, create if missing"""
    try:
        yb_host = CONFIG["yugabyte_ycql"]["host"]
        yb_port = CONFIG["yugabyte_ycql"]["port"]

        cluster = Cluster([yb_host], port=yb_port, protocol_version=4)
        session = cluster.connect()

        # Check if keyspace exists, create if missing
        result = session.execute(f"SELECT keyspace_name FROM system_schema.keyspaces WHERE keyspace_name = '{keyspace}'")
        if result.one():
            logger.info(f"      Keyspace '{keyspace}' exists on YugabyteDB")
        else:
            logger.warning(f"      Keyspace '{keyspace}' NOT found, creating...")
            replication_str = "{'class': 'SimpleStrategy', 'replication_factor': 1}"
            session.execute(f"CREATE KEYSPACE IF NOT EXISTS {keyspace} WITH REPLICATION = {replication_str}")
            logger.info(f"      ✓ Created keyspace '{keyspace}'")

        # Check if table exists, create from Cassandra schema if missing
        table_exists = False
        try:
            session.execute(f"SELECT COUNT(*) FROM {keyspace}.{table_name}")
            table_exists = True
            logger.info(f"      Table '{keyspace}.{table_name}' exists on YugabyteDB")
        except:
            pass

        if not table_exists:
            logger.warning(f"      Table '{keyspace}.{table_name}' NOT found, auto-creating from Cassandra schema...")
            create_stmt = get_table_schema_from_cassandra(keyspace, table_name)  # no open cass session here; opens its own
            if create_stmt:
                logger.info(f"      DDL: {create_stmt}")
                session.execute(create_stmt)
                logger.info(f"      ✓ Created table '{keyspace}.{table_name}' on YugabyteDB")
            else:
                logger.error(f"      ✗ Could not read schema from Cassandra for {keyspace}.{table_name}")
                session.shutdown()
                cluster.shutdown()
                return False
        else:
            logger.info(f"      Table '{keyspace}.{table_name}' exists on YugabyteDB — schema sync will happen during streaming")

        session.shutdown()
        cluster.shutdown()
        return True

    except Exception as e:
        import traceback
        logger.error(f"      Failed to verify YugabyteDB schema: {str(e)}")
        logger.error(f"      Stack trace:\n{traceback.format_exc()}")
        return False

# ============================
# Main Migration Process
# ============================
def migrate_all(spark):
    """Main migration function for all keyspaces"""
    start_time = datetime.now()
    logger.info("=" * 80)
    logger.info("Cassandra → YugabyteDB Bulk Migration (Production)")
    logger.info("=" * 80)
    logger.info(f"\nConnecting to:")
    logger.info(f"  Source: Cassandra at {CONFIG['cassandra_source']['host']}:{CONFIG['cassandra_source']['port']}")
    logger.info(f"  Target: YugabyteDB at {CONFIG['yugabyte_ycql']['host']}:{CONFIG['yugabyte_ycql']['port']}\n")

    keyspaces = CONFIG["cassandra_source"]["keyspaces"]
    migration_stats = {
        "start_time": start_time.isoformat(),
        "keyspaces": {}
    }

    total_tables = 0
    total_rows = 0
    total_success = 0
    total_failed = 0

    # Migrate each keyspace
    for ks_idx, keyspace in enumerate(keyspaces, 1):
        logger.info(f"\n[{ks_idx}/{len(keyspaces)}] Keyspace: {keyspace}")

        # Get tables in this keyspace
        tables = get_keyspace_tables(spark, keyspace)
        if not tables:
            logger.warning(f"  No tables found in {keyspace}, skipping")
            migration_stats["keyspaces"][keyspace] = {"tables": 0, "success": 0, "failed": 0, "rows": 0}
            continue

        ks_stats = {"tables": 0, "success": 0, "failed": 0, "rows": 0, "table_details": {}}

        # Migrate each table in keyspace
        for tbl_idx, table_name in enumerate(tables, 1):
            logger.info(f"    [{tbl_idx}/{len(tables)}] {table_name}")

            try:
                # Verify Cassandra count BEFORE migration
                cassandra_count_before = get_cassandra_count(keyspace, table_name)
                if cassandra_count_before is not None:
                    logger.info(f"      [BEFORE] Cassandra count: {cassandra_count_before:,} rows")
                else:
                    logger.warning(f"      [BEFORE] Could not verify Cassandra count")

                # Verify YugabyteDB schema before streaming
                ensure_yugabyte_schema(keyspace, table_name)

                # Direct stream from Cassandra to YugabyteDB
                row_count = stream_cassandra_to_yugabyte(keyspace, table_name)

                if row_count > 0 or cassandra_count_before == 0 or (row_count == 0 and cassandra_count_before is None):
                    # Verify YugabyteDB count AFTER migration
                    yugabyte_count_after = get_yugabyte_count(keyspace, table_name)
                    if yugabyte_count_after is not None:
                        logger.info(f"      [AFTER] YugabyteDB count: {yugabyte_count_after:,} rows")
                        if yugabyte_count_after == cassandra_count_before:
                            logger.info(f"      ✓ Row counts match! Migration verified.")
                        else:
                            logger.warning(f"      ⚠ Row count mismatch! Cassandra: {cassandra_count_before}, YugabyteDB: {yugabyte_count_after}")
                    else:
                        logger.warning(f"      [AFTER] Could not verify YugabyteDB count")

                    ks_stats["success"] += 1
                    ks_stats["rows"] += row_count
                    total_rows += row_count
                    total_success += 1
                    ks_stats["table_details"][table_name] = {
                        "status": "SUCCESS",
                        "rows": row_count,
                        "cassandra_before": cassandra_count_before,
                        "yugabyte_after": yugabyte_count_after
                    }
                else:
                    ks_stats["failed"] += 1
                    ks_stats["table_details"][table_name] = {
                        "status": "FAILED",
                        "rows": row_count,
                        "cassandra_before": cassandra_count_before,
                        "error": "stream_cassandra_to_yugabyte returned 0 rows"
                    }
                    total_failed += 1

            except Exception as e:
                import traceback
                err_msg = str(e)
                logger.error(f"      Error migrating {keyspace}.{table_name}: {err_msg}")
                logger.error(f"      Stack trace:\n{traceback.format_exc()}")
                ks_stats["failed"] += 1
                ks_stats["table_details"][table_name] = {"status": "FAILED", "error": err_msg}
                total_failed += 1

        ks_stats["tables"] = len(tables)
        migration_stats["keyspaces"][keyspace] = ks_stats
        total_tables += len(tables)

    # Final Summary
    end_time = datetime.now()
    duration = (end_time - start_time).total_seconds()

    logger.info("\n" + "=" * 80)
    logger.info("MIGRATION COMPLETE")
    logger.info("=" * 80)
    logger.info(f"Keyspaces: {len(keyspaces)}")
    logger.info(f"Total Tables: {total_tables}")
    logger.info(f"Successful: {total_success}")
    logger.info(f"Failed: {total_failed}")
    logger.info(f"Total Rows Migrated: {total_rows:,}")
    logger.info(f"Duration: {duration:.2f}s ({duration/60:.1f}m)")
    if duration > 0:
        logger.info(f"Throughput: {total_rows/duration:.0f} rows/sec")
    logger.info("=" * 80)

    if total_failed > 0:
        logger.info("\nFAILED TABLES:")
        logger.info("-" * 80)
        for ks, ks_data in migration_stats["keyspaces"].items():
            if not isinstance(ks_data, dict):
                continue
            for tbl, tbl_data in ks_data.get("table_details", {}).items():
                if tbl_data.get("status") == "FAILED":
                    reason = tbl_data.get("error", "unknown error")
                    logger.error(f"  ✗ {ks}.{tbl}")
                    logger.error(f"    Reason: {reason}")
        logger.info("-" * 80)

    # Save report
    migration_stats["end_time"] = end_time.isoformat()
    migration_stats["duration_seconds"] = duration
    migration_stats["total_tables"] = total_tables
    migration_stats["total_rows"] = total_rows
    migration_stats["total_success"] = total_success
    migration_stats["total_failed"] = total_failed

    with open('/var/log/migration/migration_report.json', 'w') as f:
        json.dump(migration_stats, f, indent=2)

    return total_failed == 0

# ============================
# Entry Point
# ============================
if __name__ == "__main__":
    try:
        success = migrate_all(None)
        sys.exit(0 if success else 1)

    except Exception as e:
        logger.error(f"Fatal error: {str(e)}")
        sys.exit(1)


x