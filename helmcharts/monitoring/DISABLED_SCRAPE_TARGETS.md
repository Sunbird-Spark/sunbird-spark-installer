# Disabled scrape targets

Prometheus was OOMKilling repeatedly on `cossdev` even at 4Gi/8Gi (see
`helmcharts/global-resources.yaml`'s `kube-prometheus-stack.prometheus`
resources). The components below were all newly enabled in the
`chore/grafana-dashboard-cleanup` branch and are not present in `v1.1.1` --
disabling them was the fix, until Prometheus has more headroom or the
underlying cardinality is reduced.

None of the Grafana dashboards were changed or removed. They'll just show
"No data" for these components until scraping is turned back on.

## Flink jobs (biggest driver -- 72 targets, high-cardinality `task_name`/`task_attempt_id` labels)

- `helmcharts/knowledgebb/charts/flink/values.yaml`
- `helmcharts/learnbb/charts/flink/values.yaml`

Both have `serviceMonitor.enabled: false`. Set to `true` to re-enable.
Affects the "Flink Pipelines" dashboard.

## py-flink (enrichment-router, caption-generator)

- `helmcharts/knowledgebb/charts/py-flink/values.yaml`

`serviceMonitor.enabled: false`. Set to `true` to re-enable.

## Kafka exporter

- `helmcharts/edbb/charts/kafka/values.yaml` (`metrics.kafkaExporter.enabled: false`)

Set to `true` to re-enable. This is a whole extra Deployment (not just a
scrape toggle), so re-enabling redeploys the exporter pod itself. Affects
the secor dashboard's "Topics partition count", "Topics current offset",
and "telemetry-ingest-backup lag" panels, plus `kafka_brokers`/
`kafka_topic_partitions`/etc. everywhere else they're used.

## YugabyteDB

- `helmcharts/edbb/values.yaml`
- `helmcharts/learnbb/values.yaml`
- `helmcharts/knowledgebb/values.yaml`

Each has a commented-out `serviceMonitor.extraLabels: {release: monitoring}`
under the `yugabyte:` block. Uncomment it to re-enable. Affects the
"YugabyteDB" dashboard.

## OpenSearch

- `helmcharts/learnbb/values.yaml`
- `helmcharts/knowledgebb/values.yaml`

Each has a commented-out `serviceMonitor.labels: {release: monitoring}`
under the `opensearch:` block. Uncomment it to re-enable.

## Velero

- `helmcharts/additional/charts/velero/values.yaml`

Two commented-out blocks: `metrics.service.labels` and
`metrics.nodeAgentPodMonitor.additionalLabels`, both `{release: monitoring}`.
Uncomment both to re-enable. Affects the "Backup" dashboard.

## Left enabled (not part of the memory problem)

- **Kong's `prometheus-servicemonitor.yaml`** -- a single low-cardinality
  target, and its enable flag is shared with pre-existing (v1.1.1)
  PrometheusRule alert rules, so disabling it would have broken those
  for no meaningful memory savings.
- Everything not listed above (nginx-public-ingress, node-exporter,
  kube-state-metrics, blackbox-exporter, apiserver/kubelet/coredns, etc.)
  -- all pre-existing in v1.1.1, not part of this branch's additions.

## Re-enabling

1. Flip the flags above back on (uncomment/set `true`).
2. Redeploy the affected bundle(s): `edbb` (kafka), `learnbb` and
   `knowledgebb` (flink, py-flink, yugabyte, opensearch), `additional`
   (velero).
3. Check Prometheus isn't OOMing again before assuming it's fine:
   `kubectl get pod prometheus-monitoring-kube-prometheus-prometheus-0 -n sunbird`
   -- watch `RESTARTS` for a minute or two after each bundle you re-enable,
   rather than re-enabling everything at once.
