# ai-pipeline

Restate-based replacement for the retired `py-flink` chart (`enrichment-router` +
`caption-generator`). See the design doc: *AI Pipeline on Kubernetes — PyFlink Decommission &
Restate Deployment Plan* (Obsidian design notes) for full background and rationale.

## Prerequisite: the `restate-operator` (not part of this chart)

This chart creates a `RestateCluster` and one `RestateDeployment` per workflow/service unit —
both are custom resources understood by the **`restate-operator`**, which is *not* installed by
this chart. It's a cluster-wide install (its own CRDs, its own namespace), done once, separately:

```bash
helm install restate-operator \
  oci://ghcr.io/restatedev/restate-operator-helm \
  --namespace restate-operator --create-namespace
```

Until that's installed, `RestateCluster`/`RestateDeployment` resources from this chart will sit
un-reconciled (Kubernetes will accept them, since the CRDs must already exist for that, but
nothing will act on them).

## What this chart deploys

- **`RestateCluster`** (`templates/restate/restatecluster.yaml`) — single-node to start
  (`ai-pipeline.enabled=true`, no clustering yet; see design doc §5 for the deliberate reasoning).
- **core-api** (`templates/core-api/`) — the workflow registry / control-plane API. Owns the
  catalogue database (points at the shared YugabyteDB YSQL port, not a dedicated Postgres).
- **One `RestateDeployment` per unit** (`templates/units/`) — driven by `.Values.units`, currently
  just `transcript`. Each unit self-registers with core-api on boot (`@ai-pipeline/runtime`'s
  `serve()`, `POST /v1/deployments` — unchanged, the same endpoint the CLI itself uses), which
  also wires up its Kafka triggers — no separate sidecar or Job needed for this.
- **Provisioning jobs** (`templates/provision/`):
  - `catalogue-migrate.yaml` — applies core-api's catalogue schema against YugabyteDB (mirrors
    the existing `provision/ycql.yaml` pattern, but over YSQL instead of YCQL).

## Known open items (see design doc for full detail — not resolved here)

1. Confirm YugabyteDB's `pg_advisory_lock` support against the exact pinned build
   (`yugabytedb/yugabyte:2025.2.0.0-b131`) before trusting core-api against it in anger.
2. This chart's own Kafka topic provisioning now follows the `{{ .Values.global.env }}.*`
   convention, but `workflows/transcript/metadata.json`'s trigger topic is a literal
   (`sunbirddev.content.published`) baked into the image at build time — Helm has no reach into
   an already-built image's JSON, so this can't be templated the same way. Hardcoded to `dev` for
   now; a real per-environment mechanism (metadata.json placeholder + env var resolved at boot)
   is deferred.
3. Workload Identity (OIDC) readiness for the `transcript` unit's ServiceAccount — not confirmed.
