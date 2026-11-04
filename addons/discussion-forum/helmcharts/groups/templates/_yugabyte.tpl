{{- /*
Where every service finds YugabyteDB: the in-cluster one installed by this
chart (default), or a managed one (YugabyteDB Aeon) when
global.yugabyte_managed.enabled is true.

Usage: {{ include "sunbird.yugabyte" (list $ "<key>") }}
  key: host | port | postgresql_port | username | password | user | ysql.user | ysql.password

In-cluster mode returns global.yugabyte.<key> unchanged. Managed mode returns
the matching global.yugabyte_managed value; every user key maps to
yugabyte_managed.username and every password key to yugabyte_managed.password.
*/ -}}

{{- define "sunbird.yugabyteManaged" -}}
{{- if dig "yugabyte_managed" "enabled" false (.Values.global | default dict) -}}true{{- end -}}
{{- end -}}

{{- define "sunbird.yugabyte" -}}
{{- $ctx := index . 0 -}}
{{- $key := index . 1 -}}
{{- if include "sunbird.yugabyteManaged" $ctx -}}
{{- $managed := $ctx.Values.global.yugabyte_managed -}}
{{- $field := get (dict "host" "host" "port" "port" "postgresql_port" "postgresql_port" "username" "username" "user" "username" "ysql.user" "username" "password" "password" "ysql.password" "password") $key -}}
{{- $defaults := dict "port" "9042" "postgresql_port" "5433" -}}
{{- index $managed $field | default (get $defaults $field) -}}
{{- else -}}
{{- $value := $ctx.Values.global.yugabyte -}}
{{- range (splitList "." $key) -}}
{{- if kindIs "map" $value -}}
{{- $value = index $value . -}}
{{- else -}}
{{- $value = "" -}}
{{- end -}}
{{- end -}}
{{- $value | default "" -}}
{{- end -}}
{{- end -}}
