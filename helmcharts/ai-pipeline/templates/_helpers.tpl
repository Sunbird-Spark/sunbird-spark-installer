{{/*
Qualify a bare Service name with its namespace + cluster domain (e.g. "kafka" ->
"kafka.sunbird.svc.cluster.local"). A host that already contains a dot (already
FQDN, or an external host) passes through unchanged.
Usage: {{ include "ai-pipeline.qualifyHost" (dict "host" .Values.global.kafka.host "namespace" .Values.global.kafkaNamespace "domain" .Values.global.clusterDomain) }}
*/}}
{{- define "ai-pipeline.qualifyHost" -}}
{{- if contains "." .host -}}
{{- .host -}}
{{- else -}}
{{- printf "%s.%s.svc.%s" .host .namespace .domain -}}
{{- end -}}
{{- end -}}
