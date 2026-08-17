# crds subchart

See: [https://github.com/prometheus-community/helm-charts/issues/3548](https://github.com/prometheus-community/helm-charts/issues/3548)

## DHI migration: CRD version fix (2026-08-17)

- Updated `crds/crd-prometheuses.yaml` and `crds/crd-alertmanagers.yaml` 
- Matching `v0.93.1` verison
- Supports `.status.selector` (Alertmanager) and `.status.shardStatuses[]` (Prometheus)

Visit to see the latest changes: [https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.93.1/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml](https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.93.1/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml) | [https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.93.1/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagers.yaml](https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.93.1/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagers.yaml)

