#!/bin/bash
##########################################################
# PostgreSQL to YugabyteDB Direct Migration
# Dumps each database and restores into YugabyteDB YSQL
##########################################################

set -e

# ============================
# Configuration from Helm values
# ============================
POSTGRES_HOST="{{ .Values.postgres.host }}"
POSTGRES_PORT="{{ .Values.postgres.port }}"
POSTGRES_USER="{{ .Values.postgres.username }}"
POSTGRES_PASSWORD="{{ .Values.postgres.password }}"
DATABASES="{{ .Values.postgres.databases | join " " }}"

YUGABYTE_HOST="{{ .Values.yugabyte.host }}"
YUGABYTE_PORT="{{ .Values.yugabyte.sqlPort }}"
YUGABYTE_USER="{{ .Values.yugabyte.username }}"
YUGABYTE_PASSWORD="{{ .Values.yugabyte.password }}"

LOG_FILE="/var/log/migration/migration.log"

# ============================
# Logging
# ============================
log_info()    { echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "$LOG_FILE"; }
log_success() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $*"     | tee -a "$LOG_FILE"; }
log_error()   { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE"; }

# ============================
# Migrate single database
# ============================
migrate_database() {
    local POSTGRES_DB="$1"
    local YUGABYTE_DB="$1"
    local DUMP_FILE="/tmp/${POSTGRES_DB}_dump.sql"

    log_info "=========================================="
    log_info "Migrating: $POSTGRES_DB"
    log_info "Source: PostgreSQL $POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"
    log_info "Target: YugabyteDB $YUGABYTE_HOST:$YUGABYTE_PORT/$YUGABYTE_DB"
    log_info "=========================================="

    # Full dump (schema + data) from PostgreSQL
    log_info "Dumping database '$POSTGRES_DB' from PostgreSQL..."
    PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
        -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        --no-owner \
        --no-privileges \
        -f "$DUMP_FILE"

    log_success "Dump complete: $(du -h "$DUMP_FILE" | cut -f1)"

    # Create database in YugabyteDB if not exists
    log_info "Creating database '$YUGABYTE_DB' in YugabyteDB if not exists..."
    PGPASSWORD="$YUGABYTE_PASSWORD" psql \
        -h "$YUGABYTE_HOST" -p "$YUGABYTE_PORT" \
        -U "$YUGABYTE_USER" -d yugabyte \
        -c "CREATE DATABASE \"$YUGABYTE_DB\";" 2>&1 | grep -v "already exists" | tee -a "$LOG_FILE" || true

    # Restore into YugabyteDB
    log_info "Restoring into YugabyteDB '$YUGABYTE_DB'..."
    PGPASSWORD="$YUGABYTE_PASSWORD" psql \
        -h "$YUGABYTE_HOST" -p "$YUGABYTE_PORT" \
        -U "$YUGABYTE_USER" -d "$YUGABYTE_DB" \
        -v ON_ERROR_STOP=0 \
        -f "$DUMP_FILE" 2>&1 | tee -a "$LOG_FILE"

    log_success "Restore complete for $YUGABYTE_DB"

    # Row count comparison
    log_info "Row counts comparison after migration:"
    while IFS='|' read -r tschema tname; do
        tschema=$(echo "$tschema" | xargs)
        tname=$(echo "$tname" | xargs)
        pg_count=$(PGPASSWORD="$POSTGRES_PASSWORD" psql \
            -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
            -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
            -t -c "SELECT COUNT(*) FROM \"$tschema\".\"$tname\"" | tr -d ' ')
        yb_count=$(PGPASSWORD="$YUGABYTE_PASSWORD" psql \
            -h "$YUGABYTE_HOST" -p "$YUGABYTE_PORT" \
            -U "$YUGABYTE_USER" -d "$YUGABYTE_DB" \
            -t -c "SELECT COUNT(*) FROM \"$tschema\".\"$tname\"" 2>/dev/null | tr -d ' ' || echo "0")
        if [ "$pg_count" = "$yb_count" ]; then
            log_success "  $tschema.$tname: PostgreSQL=$pg_count | YugabyteDB=$yb_count ✓ MATCH"
        else
            log_error "  $tschema.$tname: PostgreSQL=$pg_count | YugabyteDB=$yb_count ✗ MISMATCH"
        fi
    done < <(PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
        -t -c "SELECT table_schema, table_name FROM information_schema.tables
               WHERE table_type='BASE TABLE' AND table_schema NOT IN ('pg_catalog','information_schema')
               ORDER BY table_schema, table_name" | grep '|')

    log_success "Migration complete: PostgreSQL/$POSTGRES_DB → YugabyteDB/$YUGABYTE_DB"

    rm -f "$DUMP_FILE"
}

# ============================
# Main
# ============================
log_info "=========================================="
log_info "PostgreSQL → YugabyteDB Migration"
log_info "Databases to migrate: $DATABASES"
log_info "=========================================="

FAILED=0
for DB in $DATABASES; do
    migrate_database "$DB" || { log_error "Migration failed for database: $DB"; FAILED=1; }
done

if [ "$FAILED" -eq 1 ]; then
    log_error "One or more database migrations failed"
    exit 1
fi

log_success "All databases migrated successfully"
