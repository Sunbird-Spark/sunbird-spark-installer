{{- /*
Resolves which database backend's host/port a CQL (Cassandra-protocol) or
YSQL (Postgres-protocol) consumer should actually connect to, based on
global.use_cassandra_postgres. Every consumer calls these instead of reading
global.yugabyte, global.cassandra, or global.postgresql directly, so
flipping that one flag repoints every consumer at once.
*/ -}}

{{- define "sunbird.cassandraHost" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.cassandra.host }}
{{- else -}}
{{ .Values.global.yugabyte.host }}
{{- end -}}
{{- end -}}

{{- define "sunbird.cassandraPort" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.cassandra.port }}
{{- else -}}
{{ .Values.global.yugabyte.port }}
{{- end -}}
{{- end -}}

{{- define "sunbird.postgresHost" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.postgresql.host }}
{{- else -}}
{{ .Values.global.yugabyte.host }}
{{- end -}}
{{- end -}}

{{- define "sunbird.postgresPort" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.postgresql.port }}
{{- else -}}
{{ .Values.global.yugabyte.postgresql_port }}
{{- end -}}
{{- end -}}

{{- define "sunbird.postgresUsername" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.postgresql.postgresqlUsername }}
{{- else -}}
{{ .Values.global.yugabyte.username }}
{{- end -}}
{{- end -}}

{{- define "sunbird.postgresPassword" -}}
{{- if .Values.global.use_cassandra_postgres -}}
{{ .Values.global.postgresql.postgresqlPassword }}
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
