# ai-pipeline

Restate-based AI enrichment pipeline, replacing py-flink's enrichment-router/caption-generator.
Wired into `install.sh` as an opt-in top-level component — installed only when
`ai_pipeline_enabled: true` is set in the environment's `global-values.yaml`.

## Structure

- `charts/core-api` — workflow registry/control-plane (REST API, Postgres-backed catalogue).
- `charts/litellm` — LLM gateway used by the units, configured via `charts/litellm/configs/config.yaml`.
- `charts/restate-operator-helm` — upstream Restate operator (vendored dependency).
- `templates/units/restatedeployment.yaml` — one `RestateDeployment` per entry in `values.yaml`'s
  `units` map (currently `transcript`, `whisper`); self-register with Restate on boot.
- `templates/restate/restatecluster.yaml` — the `RestateCluster` CR the units register against.
- `templates/provision/` — pre-install/pre-upgrade Job that creates core-api's catalogue database.
- `crds/` — Restate CRDs extracted from the upstream operator's templated subchart so Helm's
  native `crds/` ordering guarantee applies; `install.sh` also `kubectl apply`s them directly as a
  first-install safety net (`installCrds: false` in `values.yaml`).

## Env vars and config

`core-api` and `litellm` follow knowledgebb's convention: a per-subchart `configs/env.yaml`
renders into a `-env` ConfigMap, consumed via `envFrom`. Non-env config files (e.g. litellm's
`config.yaml`) live alongside it in `configs/` and get mounted as files instead.

## Resources

Per-component `resources` defaults live in each subchart's own `values.yaml` (and
`units.<name>.resources` in this chart's `values.yaml`). Production installs override them
centrally via `helmcharts/global-resources.yaml` (`core-api`, `litellm`, `units.transcript`,
`units.whisper` keys), same mechanism knowledgebb's subcharts use.
