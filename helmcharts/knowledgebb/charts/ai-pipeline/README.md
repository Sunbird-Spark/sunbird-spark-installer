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

## How a unit gets registered — and why its URL changes

Each unit is registered with Restate twice, and both registrations must name the same endpoint:

1. **The restate-operator** registers every *version* of a `RestateDeployment`'s pod template at
   `http://<name>-<pod-template-hash>.<namespace>.svc.<clusterDomain>:9080/`. It creates one
   ReplicaSet and one Service per version, so an old version keeps serving until the invocations
   pinned to it finish; then it scales that version to zero. Any change to the pod template —
   image tag, an env value, resources — is a new version at a new URL. That is expected; do not try
   to pin it.
2. **The unit itself** posts its build to core-api on boot, and core-api registers
   `ADVERTISED_ENDPOINT` with Restate as well. This is the only way the catalogue and the Kafka
   triggers learn of a build.

`ADVERTISED_ENDPOINT` is therefore built when the pod starts, from its own `pod-template-hash`
label (downward API), and never written into the template: a literal hash in the template would
itself change the template, and so the hash — the URL would move on every deploy. With the same URL
on both sides, Restate answers whichever registration comes second with the first one's deployment
id, so there is exactly one Restate deployment per version.

`minReadySeconds` (default 30) holds a new version back from the operator until its pods have
stayed up that long. A build core-api refuses (for instance a changed artifact under an unchanged
`version`: `VERSION_ARTIFACT_CONFLICT`) exits within seconds, so the operator never routes to it and
the `RestateDeployment` reports `Ready=False` instead.

### Network access

The operator puts the Restate namespace behind a deny-all `NetworkPolicy`: the admin API is open to
the operator only, ingress to no one, and egress reaches DNS, public addresses and pods the operator
labels (every `RestateDeployment` pod). `restatecluster.yaml` opens the admin and ingress ports to
core-api and egress to the Kafka brokers (`restate.kafkaPodLabels`) in this release's namespace.
Without them, core-api waits at boot for an admin API it cannot reach, and Restate cannot consume
trigger topics. For the same reason, core-api hands Restate a fully-qualified Kafka address:
Restate resolves it from its own namespace.

### Kafka cluster name

`coreApi.kafka.clusterName` is the name Restate knows the Kafka cluster by, not the environment.
It must equal the `cluster` of every unit's Kafka trigger in its `metadata.json` (`local` today):
Restate subscribes to `kafka://<cluster>/<topic>` and refuses a cluster name it does not know.

## Known open items (see design doc for full detail — not resolved here)

1. Nothing creates the `ai_pipeline_catalogue` database or the `ai_pipeline` role in YugabyteDB;
   `catalogue-migrate` assumes both exist. Create them by hand before the first install for now.
2. The Kafka topic name `sunbirddev.enrichment.request` (from `workflows/transcript/metadata.json`)
   does not yet follow this repo's `{{ .Values.global.env }}.*` templating convention — reconcile
   before this is real production config.
3. Workload Identity (OIDC) readiness for the `transcript` unit's ServiceAccount — not confirmed.
4. A drained version stays registered in Restate — the operator scales it to zero and keeps it for
   rollback — so core-api lists it as `draining`. Retire it through core-api
   (`DELETE /v1/deployments/<deploymentId>`, refused while anything is pinned to it) once it is no
   longer needed; that works alongside the operator.

YugabyteDB's session advisory locks, which core-api takes on every registration, were checked
against the pinned build (`yugabytedb/yugabyte:2025.2.0.0-b131`, default flags): a second session
cannot take a held lock and can once it is released.
