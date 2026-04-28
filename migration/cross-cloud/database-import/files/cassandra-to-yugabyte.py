#!/usr/bin/env python3
# Cassandra -> YugabyteDB loader (cross-cloud).
# Downloads {keyspace}.tar.gz blobs (schema.cql + per-table CSVs),
# applies schema with transactions clause + keyspace rename,
# loads CSV data with blob/counter/UUID/collection parsing.
# Logic ported from migration/db-migration/files/cassandra_to_yugabyte.py.

import os
import re
import csv
import ast
import sys
import time
import uuid
import json
import tarfile
import tempfile
import logging
from collections import namedtuple
from datetime import datetime
from decimal import Decimal

from cassandra.cluster import Cluster, BatchStatement
from cassandra import ConsistencyLevel
from azure.storage.blob import BlobServiceClient

# ============================
# CONFIG
# ============================
CONFIG = {
    "storage": {
        "account":   os.environ.get("AZURE_STORAGE_ACCOUNT"),
        "key":       os.environ.get("AZURE_STORAGE_KEY"),
        "container": os.environ.get("STORAGE_CONTAINER"),
        "prefix":    os.environ.get("STORAGE_PREFIX", "cassandra"),
    },
    "ycql": {
        "host":         os.environ.get("YCQL_HOST"),
        "port":         int(os.environ.get("YCQL_PORT", "9042")),
        "sourcePrefix": os.environ.get("SOURCE_PREFIX", ""),
        "targetPrefix": os.environ.get("TARGET_PREFIX", ""),
    },
    # TRUNCATE_BEFORE_LOAD=true clears each table before inserting.
    # Required for idempotency: without it, retried jobs accumulate rows with
    # different primary-key encodings from previous (possibly broken) runs.
    "truncateBeforeLoad": os.environ.get("TRUNCATE_BEFORE_LOAD", "true").lower() == "true",
}

# Tables that require WITH transactions = {'enabled': 'true'} on YCQL.
# Mirrors sunbird-yugabyte-migrations CQL (same set as db-migration script).
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

# ============================
# LOGGING
# ============================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
log = logging.getLogger(__name__)
# Silence cassandra-driver per-connection chatter (load_balancing_policy warnings,
# host discovery, datacenter detection). Only show ERROR.
for noisy in ("cassandra", "cassandra.cluster", "cassandra.policies",
              "cassandra.pool", "cassandra.connection"):
    logging.getLogger(noisy).setLevel(logging.ERROR)


# ============================
# CONFIG VALIDATION
# ============================
def validate_config():
    if not CONFIG["storage"]["account"]:
        raise Exception("AZURE_STORAGE_ACCOUNT missing")
    if not CONFIG["storage"]["key"]:
        raise Exception("AZURE_STORAGE_KEY missing")
    if not CONFIG["storage"]["container"]:
        raise Exception("STORAGE_CONTAINER missing")
    if not CONFIG["ycql"]["host"]:
        raise Exception("YCQL_HOST missing")


def rename_keyspace(ks):
    src = CONFIG["ycql"]["sourcePrefix"]
    tgt = CONFIG["ycql"]["targetPrefix"]
    if src and ks.startswith(src):
        return ks.replace(src, tgt, 1)
    return ks


def transactional_set_for_target():
    # Env-prefixed dynamic tables — use target prefix as env so post-rename names match.
    env = CONFIG["ycql"]["targetPrefix"].rstrip("_") or os.environ.get("ENV", "sb")
    dyn = {
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
    return TRANSACTIONAL_TABLES | dyn


# ============================
# AZURE BLOB
# ============================
def get_blob_service():
    conn = (
        f"DefaultEndpointsProtocol=https;"
        f"AccountName={CONFIG['storage']['account']};"
        f"AccountKey={CONFIG['storage']['key']};"
        f"EndpointSuffix=core.windows.net"
    )
    return BlobServiceClient.from_connection_string(conn)


def list_blobs():
    svc = get_blob_service()
    container = svc.get_container_client(CONFIG["storage"]["container"])
    blobs = [
        b.name for b in container.list_blobs(name_starts_with=CONFIG["storage"]["prefix"])
        if b.name.endswith(".tar.gz")
    ]
    log.info(f"Found {len(blobs)} blob(s)")
    return blobs


def download_blob(blob_name):
    svc = get_blob_service()
    client = svc.get_blob_client(container=CONFIG["storage"]["container"], blob=blob_name)
    tmp = tempfile.NamedTemporaryFile(delete=False)
    tmp.write(client.download_blob().readall())
    tmp.close()
    return tmp.name


def extract_tar(path):
    d = tempfile.mkdtemp()
    with tarfile.open(path, "r:gz") as tar:
        tar.extractall(path=d)
    return d


# ============================
# YCQL CONNECT WITH RETRY
# ============================
def ycql_connect(keyspace=None, retries=5, delay=10):
    last_err = None
    for attempt in range(1, retries + 1):
        cluster = Cluster(
            [CONFIG["ycql"]["host"]],
            port=CONFIG["ycql"]["port"],
            protocol_version=4,
        )
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
                log.warning(f"  YCQL connect {attempt}/{retries} failed — retry in {delay}s ({str(e)[:80]})")
                time.sleep(delay)
    raise last_err


# ============================
# SCHEMA REWRITE + APPLY
# ============================
_STMT_SPLIT_RE = re.compile(r";\s*(?:\n|$)")


def split_cql(raw):
    # Strip cqlsh WARNINGs and blank lines. Split on ';' at EOL.
    lines = []
    for line in raw.splitlines():
        s = line.strip()
        if not s or s.startswith("WARNING") or s.startswith("--") or s.startswith("//"):
            continue
        lines.append(line)
    body = "\n".join(lines)
    return [s.strip() for s in _STMT_SPLIT_RE.split(body) if s.strip()]


def _split_table_body(stmt):
    # Split "CREATE TABLE ... (cols...) WITH ..." into (up_to_closing_paren, trailing).
    start = stmt.find("(")
    if start == -1:
        return stmt, ""
    depth = 0
    for i in range(start, len(stmt)):
        c = stmt[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return stmt[: i + 1], stmt[i + 1 :]
    return stmt, ""


def _extract_clustering_order(trailing):
    """Return the CLUSTERING ORDER BY (...) clause from a CREATE TABLE trailing string, or None."""
    m = re.search(r"CLUSTERING\s+ORDER\s+BY\s*\([^)]+\)", trailing, re.IGNORECASE)
    return m.group(0) if m else None


def rewrite_statement(stmt, source_ks, target_ks, tx_tables):
    upper = stmt.upper().lstrip()

    # cqlsh DESCRIBE sometimes emits USE statements — skip; we'll connect per-table.
    if upper.startswith("USE "):
        return None

    # Materialized views: YCQL doesn't support — skip.
    if upper.startswith("CREATE MATERIALIZED VIEW"):
        log.info(f"  skip MV: {stmt[:60]}")
        return None

    # Rename keyspace everywhere.
    if source_ks != target_ks:
        stmt = re.sub(rf"\b{re.escape(source_ks)}\b", target_ks, stmt)

    upper = stmt.upper().lstrip()

    if upper.startswith("CREATE KEYSPACE"):
        # Strip Cassandra-specific WITH, use SimpleStrategy RF=1 for YCQL.
        m = re.match(
            r"^\s*CREATE\s+KEYSPACE\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)",
            stmt, re.IGNORECASE,
        )
        if not m:
            return stmt
        ks = m.group(1)
        return (
            f"CREATE KEYSPACE IF NOT EXISTS {ks} "
            f"WITH REPLICATION = {{'class': 'SimpleStrategy', 'replication_factor': 1}}"
        )

    if upper.startswith("CREATE TYPE"):
        # Add IF NOT EXISTS if missing.
        if "IF NOT EXISTS" not in upper:
            stmt = re.sub(r"^(\s*CREATE\s+TYPE\s+)", r"\1IF NOT EXISTS ", stmt, count=1, flags=re.IGNORECASE)
        return stmt

    if upper.startswith("CREATE TABLE"):
        body, trailing = _split_table_body(stmt)
        if not body:
            return stmt
        # Add IF NOT EXISTS if missing.
        if "IF NOT EXISTS" not in body.upper():
            body = re.sub(r"^(\s*CREATE\s+TABLE\s+)", r"\1IF NOT EXISTS ", body, count=1, flags=re.IGNORECASE)
        # Pull qualified name to check transactional set.
        m = re.search(
            r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([\w\.]+)\s*\(",
            body, re.IGNORECASE,
        )
        full = m.group(1) if m else ""
        # Build WITH clause: preserve CLUSTERING ORDER BY; strip all other Cassandra-only options.
        with_parts = []
        clustering = _extract_clustering_order(trailing)
        if clustering:
            with_parts.append(clustering)
        if full in tx_tables:
            with_parts.append("transactions = {'enabled': 'true'}")
        if with_parts:
            return body + " WITH " + " AND ".join(with_parts)
        return body

    if upper.startswith("CREATE INDEX") or upper.startswith("CREATE CUSTOM INDEX"):
        # Add IF NOT EXISTS for idempotency.
        if "IF NOT EXISTS" not in upper:
            stmt = re.sub(
                r"^(\s*CREATE\s+(?:CUSTOM\s+)?INDEX\s+)",
                r"\1IF NOT EXISTS ",
                stmt, count=1, flags=re.IGNORECASE,
            )
        return stmt

    return stmt


def apply_schema(schema_cql, source_ks, target_ks):
    tx = transactional_set_for_target()
    stmts = split_cql(schema_cql)
    cluster, session = ycql_connect()
    try:
        # Guarantee keyspace first (in case schema.cql omits it).
        session.execute(
            f"CREATE KEYSPACE IF NOT EXISTS {target_ks} "
            f"WITH REPLICATION = {{'class': 'SimpleStrategy', 'replication_factor': 1}}"
        )
        for s in stmts:
            new = rewrite_statement(s, source_ks, target_ks, tx)
            if not new:
                continue
            try:
                session.execute(new)
                log.info(f"  DDL ok: {new[:100].replace(chr(10), ' ')}")
            except Exception as e:
                # Many will be idempotent failures (already exists) — log and keep going.
                log.warning(f"  DDL warn: {new[:80].replace(chr(10), ' ')} <- {str(e)[:100]}")
    finally:
        session.shutdown()
        cluster.shutdown()


# ============================
# TABLE METADATA + CSV PARSING
# ============================
def get_table_columns(keyspace, table):
    cluster, session = ycql_connect()
    try:
        rows = session.execute(
            f"SELECT column_name, type, kind, position FROM system_schema.columns "
            f"WHERE keyspace_name = '{keyspace}' AND table_name = '{table}'"
        )
        return list(rows)
    finally:
        session.shutdown()
        cluster.shutdown()


def classify_table(cols):
    counter_cols = [c.column_name for c in cols if c.type == "counter"]
    pk = sorted(
        [c for c in cols if c.kind in ("partition_key", "clustering")],
        key=lambda c: c.position,
    )
    pk_names = [c.column_name for c in pk]
    # Use lowercase keys for case-insensitive matching
    type_by_col = {c.column_name.lower(): c.type for c in cols}
    return bool(counter_cols), pk_names, counter_cols, type_by_col


def _unescape_cqlsh_text(s):
    # cqlsh COPY TO converts special chars to escape sequences BEFORE csv-writing,
    # then the csv writer escapes the leading backslash again:
    #   actual \n  →  \n (escape seq)  →  \\n in CSV file
    #   actual \\  →  \\              →  \\\\ in CSV file
    # Python csv with escapechar='\\' strips one level: \\n → \n (literal 2 chars).
    # This function restores the original characters from that intermediate form.
    result = []
    i = 0
    while i < len(s):
        if s[i] == '\\' and i + 1 < len(s):
            c = s[i + 1]
            if c == 'n':
                result.append('\n')
            elif c == 't':
                result.append('\t')
            elif c == 'r':
                result.append('\r')
            elif c == '\\':
                result.append('\\')
            else:
                result.append('\\')
                result.append(c)
            i += 2
        else:
            result.append(s[i])
            i += 1
    return ''.join(result)


def _udt_literal_to_dict(raw):
    """Convert cqlsh UDT literal `{f1: 'v1', f2: 2}` → Python dict via JSON.
    Uses regex to quote bare keys, then json.loads. Supports nested dicts/lists."""
    if not isinstance(raw, str) or not raw.startswith("{"):
        return None
    cleaned = re.sub(r"([{,]\s*)([a-zA-Z0-9_]+)\s*:", r'\1"\2":', raw)
    cleaned = cleaned.replace("'", '"')
    return json.loads(cleaned)


def parse_value(raw, cql_type, udt_map=None):
    # cqlsh COPY TO emits:
    #   blob -> 0x48656c6c6f
    #   uuid -> xxxxxxxx-xxxx-...
    #   timestamp -> 2023-01-01 00:00:00.000+0000
    #   list/set -> [a, b], {a, b}
    #   map -> {'k': 'v'}
    #   udt -> {field1: 'v1', field2: 2}
    #   null -> empty
    if raw is None or raw == "":
        return None
    t = cql_type.lower().strip()

    if t == "blob":
        s = raw[2:] if raw.startswith("0x") else raw
        return bytes.fromhex(s)
    if t in ("uuid", "timeuuid"):
        return uuid.UUID(raw)
    if t in ("int", "bigint", "smallint", "tinyint", "varint", "counter"):
        return int(raw)
    if t in ("float", "double"):
        return float(raw)
    if t == "decimal":
        return Decimal(raw)
    if t == "boolean":
        return raw.strip().lower() == "true"
    if t == "timestamp":
        # Trim timezone, keep millis.
        s = raw.replace("T", " ").strip()
        s = re.sub(r"([+\-]\d{4})$", "", s)
        for fmt in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
            try:
                return datetime.strptime(s, fmt)
            except ValueError:
                continue
        # If string parsing fails, try converting to int (millis)
        try:
            return int(raw)
        except ValueError:
            return raw
    if t == "date":
        try:
            return datetime.strptime(raw, "%Y-%m-%d").date()
        except ValueError:
            # If string parsing fails, try converting to int (days since epoch or millis)
            try:
                return int(raw)
            except ValueError:
                return raw
    if t in ("text", "varchar", "ascii", "inet"):
        return _unescape_cqlsh_text(raw)
    # Strip frozen<...> wrapper, recurse on inner type
    if t.startswith("frozen<"):
        inner = t[len("frozen<"):-1].strip()
        return parse_value(raw, inner, udt_map)
    # UDT — driver-registered namedtuple class. Convert literal -> dict -> namedtuple.
    if udt_map and t in udt_map:
        try:
            d = _udt_literal_to_dict(raw)
            if d is None:
                return raw
            cls = udt_map[t]
            # Build kwargs mapping field name -> value (None for missing)
            kwargs = {f: d.get(f) for f in cls._fields}
            return cls(**kwargs)
        except Exception:
            return raw
    if t.startswith(("list<", "set<", "map<", "tuple<")):
        try:
            v = ast.literal_eval(raw)
            # Handle inner types (e.g. map<text, date> -> convert values to date objects)
            inner = _get_inner_types(t)
            if t.startswith("map<") and len(inner) == 2:
                kt, vt = inner
                return {parse_value(str(k), kt, udt_map): parse_value(str(v), vt, udt_map) for k, v in v.items()}
            elif t.startswith(("list<", "set<")):
                it = inner[0] if inner else "text"
                # Inner element: if dict-shaped (UDT), pass raw repr; else stringify
                parsed = []
                for x in v:
                    if isinstance(x, dict):
                        # Reconstitute UDT literal so recursion can register-bind
                        lit = "{" + ", ".join(f"{k}: {repr(val)}" for k, val in x.items()) + "}"
                        parsed.append(parse_value(lit, it, udt_map))
                    else:
                        parsed.append(parse_value(str(x), it, udt_map))
                return set(parsed) if t.startswith("set<") else parsed
            return v
        except Exception:
            # Fallback: try regex-based UDT literal parse for list<frozen<UDT>>-shaped raw
            try:
                v = _udt_literal_to_dict("[" + raw.strip().lstrip("[").rstrip("]") + "]") if raw.strip().startswith("[") else None
                if v is not None:
                    inner = _get_inner_types(t)
                    it = inner[0] if inner else "text"
                    return [parse_value(json.dumps(x) if isinstance(x, dict) else str(x), it, udt_map) for x in v]
            except Exception:
                pass
            return raw
    # Unknown — try parsing as Cassandra UDT/map literal then JSON.
    try:
        d = _udt_literal_to_dict(raw)
        if d is not None:
            return d
        return json.loads(raw)
    except Exception:
        return raw


def _get_inner_types(cql_type):
    """Extract inner types from list<T>, set<T>, map<K, V>."""
    m = re.search(r"<(.*)>$", cql_type)
    if not m:
        return []
    parts = []
    current = []
    depth = 0
    for char in m.group(1):
        if char == "<":
            depth += 1
        elif char == ">":
            depth -= 1
        if char == "," and depth == 0:
            parts.append("".join(current).strip())
            current = []
        else:
            current.append(char)
    if current:
        parts.append("".join(current).strip())
    return parts


# ============================
# LOAD ONE TABLE FROM CSV
# ============================
_BATCH_BYTES_LIMIT = 10 * 1024 * 1024  # 10 MB — well under YCQL's 16 MB hard cap
_BATCH_ROW_LIMIT   = 500                # secondary guard against degenerate tiny rows


def _estimate_row_bytes(row):
    total = 0
    for v in row:
        if v is None:
            total += 4
        elif isinstance(v, (bytes, bytearray)):
            total += len(v)
        elif isinstance(v, str):
            total += len(v.encode("utf-8", errors="replace"))
        elif isinstance(v, (list, set, dict)):
            total += len(str(v))
        else:
            total += 8
    return max(total, 1)


def _flush_batch(session, stmts):
    bs = BatchStatement(consistency_level=ConsistencyLevel.ONE)
    for s in stmts:
        bs.add(s)
    session.execute(bs)


def _register_udts(cluster, session, keyspace):
    """Fetch UDTs in keyspace and register them as namedtuples on cluster.
    Returns dict {udt_name (lowercased): namedtuple_class}."""
    udt_map = {}
    try:
        rows = session.execute(
            f"SELECT type_name, field_names FROM system_schema.types "
            f"WHERE keyspace_name = '{keyspace}'"
        )
        for r in rows:
            fields = list(r.field_names) if r.field_names else []
            if not fields:
                continue
            cls = namedtuple(r.type_name, fields, rename=True)
            try:
                cluster.register_user_type(keyspace, r.type_name, cls)
                udt_map[r.type_name.lower()] = cls
            except Exception as e:
                log.warning(f"    register_user_type {keyspace}.{r.type_name} failed: {str(e)[:80]}")
    except Exception as e:
        log.warning(f"    UDT discovery failed for {keyspace}: {str(e)[:80]}")
    return udt_map


def load_table(keyspace, table, csv_path):
    cols = get_table_columns(keyspace, table)
    if not cols:
        log.warning(f"    {keyspace}.{table} has no columns in system_schema — skipping")
        return 0
    has_counter, pk_names, counter_names, type_by_col = classify_table(cols)

    cluster, session = ycql_connect(keyspace)
    udt_map = _register_udts(cluster, session, keyspace)
    try:
        if CONFIG["truncateBeforeLoad"]:
            try:
                session.execute(f"TRUNCATE {keyspace}.{table}")
            except Exception as e:
                log.warning(f"  truncate {keyspace}.{table} failed (table may not exist yet): {str(e)[:80]}")

        with open(csv_path, newline="") as f:
            # cqlsh COPY TO defaults: DELIMITER=',', QUOTE='"', ESCAPE='\'
            # escapechar='\\' is critical for correctly parsing escaped quotes in JSON.
            reader = csv.DictReader(f, quotechar='"', doublequote=True, escapechar='\\')
            fieldnames = [c.strip() for c in (reader.fieldnames or [])]
            rows = list(reader)
        if not rows:
            return 0

        converted = []
        for row_idx, r in enumerate(rows):
            try:
                # Use stripped and lowercased keys for robust matching
                row_data = {str(k).strip().lower(): v for k, v in r.items() if k is not None}
                converted.append([
                    parse_value(row_data.get(c.lower()), type_by_col.get(c.lower(), "text"), udt_map)
                    for c in fieldnames
                ])
            except Exception as e:
                log.error(f"    Skipping row {row_idx} in {keyspace}.{table} due to error: {e}")
                continue

        if has_counter:
            set_parts   = ", ".join([f"{c} = {c} + ?" for c in counter_names])
            where_parts = " AND ".join([f"{c} = ?" for c in pk_names])
            query = f"UPDATE {keyspace}.{table} SET {set_parts} WHERE {where_parts}"
            prepared = session.prepare(query)
            counter_idx = [fieldnames.index(c) for c in counter_names]
            pk_idx      = [fieldnames.index(c) for c in pk_names]
            n = 0
            for row in converted:
                bound = [row[i] for i in counter_idx] + [row[i] for i in pk_idx]
                session.execute(prepared.bind(bound))
                n += 1
            return n

        col_str      = ", ".join(fieldnames)
        placeholders = ", ".join(["?"] * len(fieldnames))
        query    = f"INSERT INTO {keyspace}.{table} ({col_str}) VALUES ({placeholders})"
        prepared = session.prepare(query)

        n = 0
        skipped = 0
        batch = []
        batch_bytes = 0
        for row_idx, row in enumerate(converted):
            try:
                bound = prepared.bind(row)
            except Exception as e:
                skipped += 1
                if skipped <= 5:
                    log.warning(f"    bind failed row {row_idx} in {keyspace}.{table}: {str(e)[:120]}")
                continue
            row_bytes = _estimate_row_bytes(row)
            if batch and (batch_bytes + row_bytes > _BATCH_BYTES_LIMIT or len(batch) >= _BATCH_ROW_LIMIT):
                _flush_batch(session, batch)
                n += len(batch)
                batch = []
                batch_bytes = 0
            batch.append(bound)
            batch_bytes += row_bytes
        if batch:
            _flush_batch(session, batch)
            n += len(batch)
        if skipped:
            log.warning(f"    {keyspace}.{table}: skipped {skipped} unbindable rows")
        return n
    finally:
        session.shutdown()
        cluster.shutdown()


def get_count(keyspace, table):
    try:
        cluster, session = ycql_connect(keyspace)
        r = session.execute(f"SELECT COUNT(*) FROM {table}")
        c = r[0][0] if r else 0
        session.shutdown()
        cluster.shutdown()
        return c
    except Exception as e:
        log.warning(f"    count failed: {str(e)[:80]}")
        return None


# ============================
# PROCESS ONE BLOB
# ============================
def process_blob(blob_name):
    source_ks = os.path.basename(blob_name).replace(".tar.gz", "")
    target_ks = rename_keyspace(source_ks)
    log.info(f"==> keyspace {source_ks} -> {target_ks}")

    tar_path    = download_blob(blob_name)
    extract_dir = extract_tar(tar_path)

    schema_path = None
    csv_files   = []
    for root, _, files in os.walk(extract_dir):
        for f in files:
            p = os.path.join(root, f)
            if f == "schema.cql":
                schema_path = p
            elif f.endswith(".csv"):
                csv_files.append(p)

    if schema_path:
        with open(schema_path) as f:
            schema_cql = f.read()
        apply_schema(schema_cql, source_ks, target_ks)
    else:
        log.warning(f"  schema.cql missing in {blob_name} — assuming target schema pre-exists")

    total = 0
    failed = 0
    mismatched = 0
    for path in csv_files:
        table = os.path.splitext(os.path.basename(path))[0]
        try:
            loaded = load_table(target_ks, table, path)
            after  = get_count(target_ks, table)
            if after is not None and after != loaded:
                mismatched += 1
                log.warning(f"  {table}: loaded {loaded} after {after} [MISMATCH]")
            total += loaded
        except Exception as e:
            failed += 1
            log.error(f"  {table}: failed {str(e)[:120]}")
    suffix = ""
    if failed:
        suffix += f" failed={failed}"
    if mismatched:
        suffix += f" mismatched={mismatched}"
    log.info(f"<== {target_ks} done: tables={len(csv_files)} rows={total}{suffix}")
    return total


# ============================
# MAIN
# ============================
def migrate():
    validate_config()
    log.info("=" * 60)
    log.info(f"Cassandra -> YugabyteDB import")
    log.info(f"  target: {CONFIG['ycql']['host']}:{CONFIG['ycql']['port']}")
    log.info(f"  rename: {CONFIG['ycql']['sourcePrefix']!r} -> {CONFIG['ycql']['targetPrefix']!r}")
    log.info("=" * 60)

    blobs = list_blobs()
    total = 0
    failed = []
    for blob in blobs:
        try:
            total += process_blob(blob)
        except Exception as e:
            log.error(f"failed blob {blob}: {e}")
            failed.append(blob)

    log.info("=" * 60)
    log.info(f"TOTAL ROWS MIGRATED: {total:,}")
    if failed:
        log.error(f"FAILED BLOBS: {failed}")
    log.info("=" * 60)
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(migrate())