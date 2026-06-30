#!/usr/bin/env python3
"""
YCQL backup using cassandra-driver.
Exports each table as CSV + schema DDL per keyspace.
"""
import argparse
import csv
import os
import sys

from cassandra.cluster import Cluster
from cassandra.policies import DCAwareRoundRobinPolicy

SYSTEM_KEYSPACES = {
    "system", "system_schema", "system_auth", "system_distributed",
    "system_traces", "system_virtual_schema", "system_views"
}


def get_keyspaces(session, requested):
    rows = session.execute("SELECT keyspace_name FROM system_schema.keyspaces")
    all_ks = [r.keyspace_name for r in rows if r.keyspace_name not in SYSTEM_KEYSPACES]
    if requested:
        return [k for k in all_ks if k in requested]
    return all_ks


def backup_keyspace(session, keyspace, output_dir):
    ks_dir = os.path.join(output_dir, keyspace)
    os.makedirs(ks_dir, exist_ok=True)

    # Schema DDL
    schema_path = os.path.join(ks_dir, "schema.cql")
    rows = session.execute(
        "SELECT * FROM system_schema.tables WHERE keyspace_name=%s", [keyspace]
    )
    tables = [r.table_name for r in rows]

    with open(schema_path, "w") as f:
        for table in tables:
            desc_rows = session.execute(
                f"DESCRIBE TABLE {keyspace}.{table}"
            )
            for row in desc_rows:
                f.write(row[0] + ";\n\n")
    print(f"  Schema written: {schema_path}")

    # Data CSV per table
    for table in tables:
        csv_path = os.path.join(ks_dir, f"{table}.csv")
        rows = session.execute(f"SELECT * FROM {keyspace}.{table}")
        if rows.column_names:
            with open(csv_path, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(rows.column_names)
                for row in rows:
                    writer.writerow(list(row))
            print(f"  Table backed up: {keyspace}.{table} → {csv_path}")
        else:
            print(f"  Skipped empty table: {keyspace}.{table}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="yb-tserver-service")
    parser.add_argument("--port", type=int, default=9042)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--keyspaces", default="",
                        help="Comma-separated keyspaces. Empty = all non-system.")
    args = parser.parse_args()

    requested = set(args.keyspaces.split(",")) - {""} if args.keyspaces else set()

    cluster = Cluster(
        [args.host],
        port=args.port,
        load_balancing_policy=DCAwareRoundRobinPolicy(local_dc="datacenter1"),
        protocol_version=4
    )
    session = cluster.connect()

    keyspaces = get_keyspaces(session, requested)
    print(f"Keyspaces to backup: {keyspaces}")

    for ks in keyspaces:
        print(f"\nBacking up keyspace: {ks}")
        try:
            backup_keyspace(session, ks, args.output_dir)
        except Exception as e:
            print(f"  ERROR backing up {ks}: {e}", file=sys.stderr)

    cluster.shutdown()


if __name__ == "__main__":
    main()
