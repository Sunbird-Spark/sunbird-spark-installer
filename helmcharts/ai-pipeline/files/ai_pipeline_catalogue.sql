-- ai-pipeline's core-api catalogue database (workflow definitions, deployments, dependencies,
-- triggers). Owned by the cluster's existing yugabyte superuser -- no dedicated role, so core-api
-- reuses whatever credentials the rest of this instance already has provisioned.
--
-- YSQL (ysqlsh/psql), not YCQL -- this is a plain Postgres-wire database, not a keyspace, so it
-- can't go through this folder's own execute_migrations.sh (ycqlsh-only). Run separately against
-- YugabyteDB's YSQL port (5433), e.g.:
--   ysqlsh -h <host> -p 5433 -U yugabyte -f ai_pipeline_catalogue.sql
--
-- CREATE DATABASE can't run inside a transaction/DO block, and YSQL (like Postgres) has no
-- `IF NOT EXISTS` for it -- \gexec is the standard idempotent workaround: only executes the
-- generated CREATE DATABASE statement when the database doesn't already exist.
SELECT 'CREATE DATABASE ai_pipeline_catalogue OWNER yugabyte'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ai_pipeline_catalogue')\gexec

-- \gexec only creates the database -- it doesn't move the session into it. Everything below runs
-- against whatever database this script's connection started in unless we switch explicitly.
\c ai_pipeline_catalogue

-- The catalogue (control-plane) store: definitions, deployments, dependencies and triggers.
-- Source of truth is ai-pipeline/infra/postgres/init/20-catalogue.sql -- keep the two in sync by
-- hand until that repo ships a proper migration tool. Execution state lives in Restate; nothing
-- here tracks runs. Written to be re-runnable (`IF NOT EXISTS` throughout).
CREATE TABLE IF NOT EXISTS workflow_definitions (
  name          text        NOT NULL,
  version       text        NOT NULL,
  kind          text        NOT NULL CHECK (kind IN ('workflow', 'service')),
  restate_name  text        NOT NULL,
  visibility    text        NOT NULL CHECK (visibility IN ('public', 'private')),
  description   text        NOT NULL DEFAULT '',
  metadata      jsonb       NOT NULL,
  input_schema  jsonb       NOT NULL,
  output_schema jsonb       NOT NULL,
  config_schema jsonb       NOT NULL,
  contract_hash text        NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (name, version)
);
CREATE INDEX IF NOT EXISTS workflow_definitions_latest ON workflow_definitions (name, updated_at DESC);

CREATE TABLE IF NOT EXISTS workflow_deployments (
  deployment_id   text        PRIMARY KEY,
  name            text        NOT NULL,
  version         text        NOT NULL,
  endpoint_uri    text        NOT NULL,
  artifact_digest text        NOT NULL,
  mode            text        NOT NULL CHECK (mode IN ('dev', 'immutable')),
  status          text        NOT NULL CHECK (status IN ('active', 'draining', 'retired')),
  registered_at   timestamptz NOT NULL DEFAULT now(),
  drained_at      timestamptz,
  FOREIGN KEY (name, version) REFERENCES workflow_definitions (name, version)
);
CREATE INDEX IF NOT EXISTS workflow_deployments_by_name ON workflow_deployments (name, registered_at DESC);

CREATE TABLE IF NOT EXISTS workflow_dependencies (
  name            text NOT NULL,
  version         text NOT NULL,
  dependency_name text NOT NULL,
  dependency_kind text NOT NULL CHECK (dependency_kind IN ('workflow', 'service')),
  PRIMARY KEY (name, version, dependency_name),
  FOREIGN KEY (name, version) REFERENCES workflow_definitions (name, version)
);

CREATE TABLE IF NOT EXISTS workflow_triggers (
  name            text        NOT NULL,
  trigger_id      text        NOT NULL,
  type            text        NOT NULL CHECK (type IN ('rest', 'kafka')),
  definition      jsonb       NOT NULL,
  desired_enabled boolean     NOT NULL DEFAULT true,
  subscription_id text,
  observed_status text        NOT NULL DEFAULT 'pending',
  last_error      text,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (name, trigger_id)
);
