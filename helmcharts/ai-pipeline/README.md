# ai-pipeline

A Restate-based pipeline for running AI workflows as independently deployable units. Opt-in
top-level component in `install.sh`, installed only when `ai_pipeline_enabled: true` is set in
the environment's `global-values.yaml`.

## What it deploys

- **RestateCluster** (`templates/restate/restatecluster.yaml`) — single-node Restate cluster that
  the pipeline's units register against. Image comes from `global.<restate.globalImageKey>`.
  Storage size via `restate.storageRequestBytes`. Network policy opens admin (9070) and ingress
  (8080) to `core-api` only, plus Kafka egress for trigger topics — not enforced on clusters
  without a NetworkPolicy CNI, but kept correct regardless.
- **restate-operator-helm** — vendored upstream operator dependency that reconciles
  `RestateCluster`/`RestateDeployment` CRs. Toggle with `restate-operator-helm.enabled`.
- **core-api** (`charts/core-api`) — workflow registry/control-plane: a REST API backed by a
  Postgres (YugabyteDB) catalogue database. Toggle with `core-api.enabled`.
- **litellm** (`charts/litellm`) — LLM gateway the units call into, configured by
  `charts/litellm/configs/config.yaml`. Toggle with `litellm.enabled`. Its Service is named
  plainly `litellm` (not release-prefixed) so units and local dev tooling can reach it at a fixed
  address.
- **Units** (`templates/units/restatedeployment.yaml`) — one `RestateDeployment` per entry in
  `values.yaml`'s `units` map. Each unit is its own container image, self-registers with Restate
  on boot, and gets its Kafka trigger topics from that image's own `metadata.json` rather than
  from this chart. Currently defined: `transcript` and `whisper`.
- **Catalogue migration Job** (`templates/provision/`) — a `pre-install,pre-upgrade` hook that
  creates core-api's database and tables from `files/ai_pipeline_catalogue.sql` before core-api's
  own Deployment starts. Idempotent and re-runnable.
- **CRDs** (`crds/`) — the three Restate CRDs (`RestateCluster`, `RestateDeployment`,
  `RestateCloudEnvironment`), vendored as static manifests rather than rendered from the operator
  subchart's own templates. Helm's native `crds/` directory installs before any template in the
  release, guaranteeing the CRDs exist before this chart's own CRs need them — relying on template
  ordering across two charts in one release can't give that guarantee. Tradeoff: these don't
  auto-upgrade on `helm upgrade`; if `restate-operator-helm`'s version bumps, re-copy the manifests
  from its `charts/restate-operator-crds/crd-manifests/`. `install.sh` also `kubectl apply`s this
  directory directly as a first-install safety net (`restate-operator-helm.installCrds: false`).

## Config and env vars

`core-api` and `litellm` each have a `configs/env.yaml` that renders into a `-env` ConfigMap,
consumed by their Deployment via `envFrom`. Non-env config files (e.g. litellm's `config.yaml`)
live alongside it in the same `configs/` directory and get mounted as files instead.

Units take their custom env vars from `units.<name>.env` (a map) and `units.<name>.secretEnv` (a
list of `{envName, secretName, secretKey}`) directly in `values.yaml`; values can contain Helm
template expressions, evaluated against the full values tree.

Hostnames for services that live outside this release's own namespace (Kafka, YugabyteDB) are
qualified from a bare Service name to a full in-cluster FQDN by the shared
`ai-pipeline.qualifyHost` named template (`templates/_helpers.tpl`), given a host, namespace, and
cluster domain.

## Resources

Each subchart/unit has its own `resources` defaults in `values.yaml`
(`charts/core-api/values.yaml`, `charts/litellm/values.yaml`, `units.<name>.resources` in this
chart's own `values.yaml`). `helmcharts/global-resources.yaml` overrides them centrally for
production installs via the `core-api`, `litellm`, `units.transcript`, and `units.whisper` keys.

## Probes

`core-api` and `litellm` define `startupProbe`/`readinessProbe`/`livenessProbe` in their own
`values.yaml`, rendered as a plain `toYaml` passthrough in their Deployments. Units
(`RestateDeployment`s) have no kubelet probes — the restate-operator's own reconciliation and
registration handshake (gated by `minReadySeconds`) is what determines when a unit version starts
receiving invocations.
