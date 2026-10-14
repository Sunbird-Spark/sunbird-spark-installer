{{- /*
CQL host/port for this addon, following the same backend switch as the
bundles' sunbird.cassandraHost / sunbird.cassandraPort helpers:
use_cassandra_postgres -> Cassandra, yugabyte_managed.enabled -> managed
YugabyteDB, otherwise in-cluster YugabyteDB.
*/ -}}

{{- define "addon.dbHost" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.cassandra.host }}
{{- else if dig "yugabyte_managed" "enabled" false (.Values.global | default dict) -}}
{{ .Values.global.yugabyte_managed.host }}
{{- else -}}
{{ .Values.global.yugabyte.host }}
{{- end -}}
{{- end -}}

{{- define "addon.dbPort" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.cassandra.port }}
{{- else if dig "yugabyte_managed" "enabled" false (.Values.global | default dict) -}}
{{ .Values.global.yugabyte_managed.port | default 9042 }}
{{- else -}}
{{ .Values.global.yugabyte.port }}
{{- end -}}
{{- end -}}
