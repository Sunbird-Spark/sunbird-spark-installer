{{/*
Expand the name of the chart.
*/}}
{{- define "database-export.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "database-export.fullname" -}}
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
{{- define "database-export.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "database-export.labels" -}}
helm.sh/chart: {{ include "database-export.chart" . }}
{{ include "database-export.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "database-export.selectorLabels" -}}
app.kubernetes.io/name: {{ include "database-export.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ConfigMap name for upload scripts
*/}}
{{- define "database-export.scriptsConfigMap" -}}
{{- printf "%s-scripts" (include "database-export.fullname" .) }}
{{- end }}

{{/*
Secret name
*/}}
{{- define "database-export.secretName" -}}
{{- printf "%s-secrets" (include "database-export.fullname" .) }}
{{- end }}
