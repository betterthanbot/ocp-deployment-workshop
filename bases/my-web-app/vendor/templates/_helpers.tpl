{{/*
Expand the name of the chart.
*/}}
{{- define "my-webapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncated at 63 chars (DNS spec limit).
*/}}
{{- define "my-webapp.fullname" -}}
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
Chart name + version label
*/}}
{{- define "my-webapp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "my-webapp.labels" -}}
helm.sh/chart: {{ include "my-webapp.chart" . }}
{{ include "my-webapp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "my-webapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "my-webapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "my-webapp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "my-webapp.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
DB port — returns the correct port number for the configured engine
*/}}
{{- define "my-webapp.dbPort" -}}
{{- if eq .Values.database.engine "postgresql" }}
{{- .Values.database.postgresql.port }}
{{- else if eq .Values.database.engine "mysql" }}
{{- .Values.database.mysql.port }}
{{- end }}
{{- end }}

{{/*
DB port name — used as the named port in the DB Service
*/}}
{{- define "my-webapp.dbPortName" -}}
{{- if eq .Values.database.engine "postgresql" -}}
postgresql
{{- else if eq .Values.database.engine "mysql" -}}
mysql
{{- end }}
{{- end }}
