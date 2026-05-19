{{/*
Expand the name of the chart.
*/}}
{{- define "database-import.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "database-import.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "database-import.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "database-import.labels" -}}
helm.sh/chart: {{ include "database-import.chart" . }}
{{ include "database-import.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "database-import.selectorLabels" -}}
app.kubernetes.io/name: {{ include "database-import.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ConfigMap name for restore scripts
*/}}
{{- define "database-import.scriptsConfigMap" -}}
{{- printf "%s-scripts" (include "database-import.fullname" .) }}
{{- end }}

{{/*
Secret name
*/}}
{{- define "database-import.secretName" -}}
{{- printf "%s-secrets" (include "database-import.fullname" .) }}
{{- end }}

{{/*
ServiceAccount name (single canonical name)
*/}}
{{- define "database-import.serviceAccountName" -}}
{{- printf "%s-sa" (include "database-import.fullname" .) }}
{{- end }}
