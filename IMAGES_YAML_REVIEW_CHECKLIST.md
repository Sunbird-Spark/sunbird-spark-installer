# images.yaml / Helm override review checklist

`helmcharts/images.yaml` is a central catalog that tries to override every
image used across all 6 building blocks. Because most of what it overrides
is **third-party vendored charts** (kube-prometheus-stack, YugabyteDB, Kong,
Loki, reloader, etc.), each with its own values schema, a change that looks
correct by pattern-matching the rest of the file can silently do nothing.
None of these failures show up as a Helm error — `helm upgrade` succeeds,
and the wrong (or default) image just quietly runs instead.

Use this checklist whenever a PR touches `images.yaml`, or any chart's
`values.yaml`/templates that consume it.

## 1. Does the override actually reach the chart's real field name?

Don't assume `image: {registry, repository, tag}` is universal. **Extract
the actual chart** (`tar -xzf helmcharts/<bb>/charts/<name>-*.tgz`) and grep
its templates for how the image string gets built, e.g.:

```bash
grep -rn "Values.*[Ii]mage" helmcharts/<bb>/charts/<name>/templates/
```

Known non-standard shapes found so far in this repo:

| Chart | Real field(s) | Notes |
|---|---|---|
| YugabyteDB (`yugabyte-*.tgz`) | `Image.repository` / `Image.tag` — **capital I** | No separate `registry` field. Combined repository string. `Image` (not `image`) is used in every template (`service.yaml` masters/tservers). Verified by extracting the chart directly. |
| statsd-exporter (kube-prometheus-stack subchart) | `image.repository` (combined) / `image.imageTag` — **`imageTag`, not `tag`** | No `registry` field. |
| reloader (`monitoring/charts/reloader`) | `reloader.image.name` / `.tag` | Field is `name`, not `repository`. No `deployment:` nesting — check the chart's own `values.yaml` before assuming otherwise. |
| grafana's admission-webhook sidecar / dashboard sidecar (`k8s_sidecar`) | `sidecar.image.repository` (combined) / `.tag` | Split registry/repository is NOT read here. |
| secor, superset (org DHI-hardened charts) | `image.repository` / `image.tag` — **no `.registry` at all** | If you set `registry:` separately in the anchor without combining it into `repository`, the pod silently tries to pull from `docker.io` instead of wherever `registry:` said. Confirmed via `edbb/charts/secor/templates/secor-statefulset.yaml` and every `obsrvbb/charts/superset/templates/deployment*.yaml`. |
| janusgraph's logstash sidecar, velero's azure plugin initContainer | plain `"repo:tag"` string, not a map at all | These are literal Kubernetes container `image:` fields — the API requires a string, never an object. Don't "fix" these to look like the other anchors. |

**Rule of thumb:** if a chart's registry isn't `docker.io`, and its
override anchor uses the split `registry:`/`repository:` shape, go verify
the template actually reads `.registry` — this is exactly the class of bug
that hit secor/superset.

## 2. Does the wiring collide with the `<<: *internal` merge?

`images.yaml` has a big `internal: &internal { ... }` block merged into the
document root via `<<: *internal`. Several top-level keys already come from
that merge: `velero`, `janusgraph`, `knowledgemw`, `kafka`, `yugabyte`,
`superset`, `secor`, etc. (see the `internal:` block for the full list).

**YAML merge-key rule: an explicit key at the same name completely replaces
the merged-in one — it does NOT deep-merge.** If you add a new explicit
top-level block for one of these names (e.g. to add `initContainers:` to
`velero`, or `sidecars:` to `janusgraph`, or `envoy_image` to `knowledgemw`),
you must **re-include that key's `image:`/`imagePullSecrets:` inside the
same block**, or the working override from `internal:` silently vanishes.

```yaml
# WRONG — silently deletes the internal: block's velero.image override
velero:
  initContainers:
    - name: velero-plugin-for-azure
      image: *velero_plugin_azure

# RIGHT — re-include what internal: already provided
velero:
  image: *velero
  imagePullSecrets:
    - name: "registry-secret-name"
  initContainers:
    - name: velero-plugin-for-azure
      image: *velero_plugin_azure
```

Before adding or reviewing any new top-level key in this file, check
whether that same key already exists inside the `internal:` block. If it
does, the new block must carry `image`/`imagePullSecrets` forward too.

## 3. Is the override actually nested at the path the chart needs?

Some images live *inside* another chart's subchart, not at that chart's
own root. Setting a same-named top-level key doesn't reach it — it has to
be nested correctly:

- Grafana is bundled inside `kube-prometheus-stack`, not its own chart —
  the path is `kube-prometheus-stack.grafana.image`, not a root-level
  `grafana:` key.
- `envoy_image`/`opa_image`/`proxy_init_image` are read *inside* the
  `knowledgemw` **subchart** of `edbb` — from within that subchart's own
  template context, `.Values` resolves against `edbb.knowledgemw.*`, so
  these have to be nested under a `knowledgemw:` block, not set at edbb's
  own root (a flat root-level key silently doesn't reach them).

If a chart the override targets is itself a dependency of another chart
(check `Chart.yaml`'s `dependencies:`), trace exactly which parent's
`.Values.<subchart-name>.*` namespace it lives in before deciding where to
place the override.

## 4. Did you check for a hardcoded literal instead of a real values field?

Some templates in this repo hardcode an image directly with no
`{{ .Values }}` around it at all — e.g. `templates/provision/job-cleaner.yaml`
(x3 building blocks), `templates/provision/ysql.yaml`,
`templates/provision/opensearch-migration.yaml`, and (before this session's
fix) `knowledgemw/templates/deployment.yaml`'s envoy/opa/proxy_init
containers. `images.yaml` has nothing to override in these cases — the
template itself has to be changed first to read a values field, with a
matching default added to the relevant chart's own `values.yaml`.

## 5. Verify, don't assume — every fix in this file should be provable

For any override you add or change, do all three of these before
considering it done:

1. `helm template <bundle> ... 2>&1 | grep <image>` — confirm the exact,
   full image string (including registry) appears where you expect.
2. **Temporarily change the value to a `-TESTPROBE` suffix**, re-render,
   confirm the probe value shows up, then revert. This is the only way to
   rule out a *coincidental* match with the chart's own unrelated default
   (this exact trap caught the `janusgraph_logstash` and `velero`
   collision bugs in this repo — the render looked "correct" purely by
   luck, because the override wasn't actually reaching anything).
3. If the image is only used inside a Job/StatefulSet's pod spec that's
   already running in a live cluster, remember Kubernetes Jobs have an
   **immutable `spec.template`** — a plain (non-hook) Job can't be patched
   in place on `helm upgrade` once its pod spec changes. Check for
   `helm.sh/hook: pre-install,pre-upgrade` + `helm.sh/hook-delete-policy:
   before-hook-creation` on any Job whose image you're changing.

## Confirmed-safe reference (as of this checklist)

These paths were verified correct via the process above — safe to treat as
ground truth without re-deriving:

```
kube-prometheus-stack.grafana.image                (registry+repository+tag)
kube-prometheus-stack.grafana.sidecar.image         (combined repository+tag)
kube-prometheus-stack.prometheusOperator.image
kube-prometheus-stack.prometheusOperator.admissionWebhooks.patch.image
kube-prometheus-stack.prometheus.prometheusSpec.image
kube-prometheus-stack.alertmanager.alertmanagerSpec.image
kube-prometheus-stack.prometheus-blackbox-exporter.image
kube-prometheus-stack.kube-state-metrics.image
kube-prometheus-stack.prometheus-node-exporter.image
kube-prometheus-stack.statsd-exporter.image         (repository combined + imageTag)
kubernetes-dashboard.api.image
kubernetes-dashboard.web.image
kubernetes-dashboard.metricsScraper.image
loki.image
loki.gateway.image
reloader.reloader.image                             (name + tag, no repository field)
velero.image + velero.initContainers[].image        (plain string) + velero.kubectl.image
janusgraph.image + janusgraph.sidecars[].image      (plain string)
knowledgemw.image + knowledgemw.{envoy,opa,proxy_init}_image
internal.yugabyte.Image                             (capital I — not image)
internal.kafka.image  +  global.kafka.image          (two separate consumers, both needed)
edbb/learnbb/knowledgebb job_cleaner_kubectl_image   (registry+repository+tag)
edbb/learnbb job_wait_image, yugabyte_migration_image, opensearch_migration_image
secor.image, superset.image                          (repository must be combined — no separate registry)
```
