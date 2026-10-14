{{- /*
Resolves which database backend a CQL (Cassandra-protocol) or YSQL
(Postgres-protocol) consumer should connect to. Every consumer calls these
instead of reading global.yugabyte, global.yugabyte_managed, global.cassandra
or global.postgresql directly, so one flag repoints every consumer at once:

  global.use_cassandra_postgres: true     -> Apache Cassandra + PostgreSQL
  global.yugabyte_managed.enabled: true   -> managed YugabyteDB (Aeon)
  neither                                 -> in-cluster YugabyteDB
*/ -}}

{{- define "sunbird.yugabyteManaged" -}}
{{- if dig "yugabyte_managed" "enabled" false (.Values.global | default dict) -}}true{{- end -}}
{{- end -}}

{{- define "sunbird.cassandraHost" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.cassandra.host }}
{{- else if include "sunbird.yugabyteManaged" . -}}
{{ .Values.global.yugabyte_managed.host }}
{{- else -}}
{{ .Values.global.yugabyte.host }}
{{- end -}}
{{- end -}}

{{- define "sunbird.cassandraPort" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.cassandra.port }}
{{- else if include "sunbird.yugabyteManaged" . -}}
{{ .Values.global.yugabyte_managed.port | default 9042 }}
{{- else -}}
{{ .Values.global.yugabyte.port }}
{{- end -}}
{{- end -}}

{{- define "sunbird.cassandraUsername" -}}
{{- if .Values.global.use_cassandra_postgres -}}
cassandra
{{- else if include "sunbird.yugabyteManaged" . -}}
{{ .Values.global.yugabyte_managed.username }}
{{- else -}}
yugabyte
{{- end -}}
{{- end -}}

{{- define "sunbird.cassandraPassword" -}}
{{- if .Values.global.use_cassandra_postgres -}}
cassandra
{{- else if include "sunbird.yugabyteManaged" . -}}
{{ .Values.global.yugabyte_managed.password }}
{{- else -}}
yugabyte
{{- end -}}
{{- end -}}

{{- define "sunbird.postgresHost" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.postgresql.host }}
{{- else if include "sunbird.yugabyteManaged" . -}}
{{ .Values.global.yugabyte_managed.host }}
{{- else -}}
{{ .Values.global.yugabyte.host }}
{{- end -}}
{{- end -}}

{{- define "sunbird.postgresPort" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.postgresql.port }}
{{- else if include "sunbird.yugabyteManaged" . -}}
{{ .Values.global.yugabyte_managed.postgresql_port | default 5433 }}
{{- else -}}
{{ .Values.global.yugabyte.postgresql_port }}
{{- end -}}
{{- end -}}

{{- define "sunbird.postgresUsername" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.postgresql.postgresqlUsername }}
{{- else if include "sunbird.yugabyteManaged" . -}}
{{ .Values.global.yugabyte_managed.username }}
{{- else -}}
{{ .Values.global.yugabyte.username }}
{{- end -}}
{{- end -}}

{{- define "sunbird.postgresPassword" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.postgresql.postgresqlPassword }}
{{- else if include "sunbird.yugabyteManaged" . -}}
{{ .Values.global.yugabyte_managed.password }}
{{- else -}}
{{ .Values.global.yugabyte.password }}
{{- end -}}
{{- end -}}

{{- define "sunbird.ysqlshShim" -}}
mkdir -p /tmp/bin
printf '#!/bin/sh\nexec psql "$@"\n' > /tmp/bin/ysqlsh
chmod +x /tmp/bin/ysqlsh
export PATH=/tmp/bin:$PATH
{{- end -}}
