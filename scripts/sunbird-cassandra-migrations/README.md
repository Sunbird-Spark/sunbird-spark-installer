# Sunbird Cassandra Migrations

CQL schema migrations for Sunbird on Apache Cassandra 5. Used by the `learnbb` and `knowledgebb` CQL provisioning jobs when `global.use_cassandra_postgres` is `true`.

These files are the Cassandra version of `scripts/sunbird-yugabyte-migrations`, with the YCQL-only syntax removed:

- `AND transactions = {'enabled': 'true'}` table option
- `read_repair_chance` / `dclocal_read_repair_chance` table options (removed in Cassandra 4.0)
- `INCLUDE (...)` and `WITH CLUSTERING ORDER BY` on secondary indexes
- multi-column secondary index `assessment_aggregator_by_user`, now on `user_id` only

When you change a schema in `sunbird-yugabyte-migrations`, make the same change here.

## Structure

```
sunbird-lern/          # Learning and user management schemas
sunbird-knowlg/        # Knowledge and content management schemas
sunbird-inquiry/       # Assessment and inquiry schemas
```

## Usage

```bash
export ENV=dev
export CQLSH_HOST=cassandra
export CQLSH_PORT=9042

cd /opt/migrations/sunbird-cassandra-migrations/sunbird-lern && ./execute_migrations.sh "$ENV"
cd /opt/migrations/sunbird-cassandra-migrations/sunbird-knowlg && ./execute_migrations.sh "$ENV"
cd /opt/migrations/sunbird-cassandra-migrations/sunbird-inquiry && ./execute_migrations.sh "$ENV"
```

`CQLSH_USERNAME` / `CQLSH_PASSWORD` default to `cassandra` and are ignored when Cassandra runs with `AllowAllAuthenticator`.

## Build

Built and pushed by `.github/workflows/build-push-images.yml` on `spark-v*` tags as `ghcr.io/sunbird-spark/sunbird-cassandra-migrations`.
