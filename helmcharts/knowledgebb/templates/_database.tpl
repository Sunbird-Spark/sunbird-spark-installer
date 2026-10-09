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

{{- define "sunbird.cassandraCompatSed" -}}
sed -E -i \
  -e "s/[[:space:]]*AND transactions = \{'enabled': 'true'\}//I" \
  -e "/^[[:space:]]*AND (dclocal_)?read_repair_chance = [0-9.]+[[:space:]]*$/Id" \
  -e "s/^([[:space:]]*)AND (dclocal_)?read_repair_chance = [0-9.]+[[:space:]]*;/\1;/I" \
  -e "s/[[:space:]]+INCLUDE[[:space:]]*\([^)]*\)//I" \
  -e "/^[[:space:]]*CREATE INDEX/I s/[[:space:]]+WITH CLUSTERING ORDER BY[[:space:]]*\([^)]*\)//I" \
  -e "s/(ON sunbird_courses\.assessment_aggregator)[[:space:]]*\(user_id,[^)]*\)/\1 (user_id)/I"
{{- end -}}

{{- define "sunbird.ycqlshShim" -}}
mkdir -p /tmp/bin
printf '#!/bin/sh\nexec cqlsh --request-timeout=120 "$@"\n' > /tmp/bin/ycqlsh
chmod +x /tmp/bin/ycqlsh
export PATH=/tmp/bin:$PATH
{{- end -}}

{{- define "sunbird.ysqlshShim" -}}
mkdir -p /tmp/bin
printf '#!/bin/sh\nexec psql "$@"\n' > /tmp/bin/ysqlsh
chmod +x /tmp/bin/ysqlsh
export PATH=/tmp/bin:$PATH
{{- end -}}
