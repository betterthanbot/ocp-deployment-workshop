{{/*
Expand the name of the chart.
*/}}
{{- define "parksmap.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to every resource.
*/}}
{{- define "parksmap.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Values.global.partOf }}
{{- end }}

{{/*
Resolve namespace: values.yaml override takes precedence,
falls back to --namespace / Release.Namespace.
*/}}
{{- define "parksmap.namespace" -}}
{{- .Values.namespace | default .Release.Namespace }}
{{- end }}

{{/*
Frontend-specific labels.
*/}}
{{- define "parksmap.frontend.labels" -}}
{{ include "parksmap.labels" . }}
app: parksmap
app.kubernetes.io/name: parksmap
app.kubernetes.io/instance: parksmap
app.kubernetes.io/component: parksmap
role: frontend
{{- end }}

{{/*
Frontend selector labels (used by Service → Pod matching).
*/}}
{{- define "parksmap.frontend.selectorLabels" -}}
app: parksmap
deployment: parksmap
{{- end }}

{{/*
Backend-specific labels.
*/}}
{{- define "parksmap.backend.labels" -}}
{{ include "parksmap.labels" . }}
app: nationalparks
app.kubernetes.io/name: nationalparks
app.kubernetes.io/instance: nationalparks
app.kubernetes.io/component: nationalparks
role: backend
{{- end }}

{{/*
Backend selector labels.
*/}}
{{- define "parksmap.backend.selectorLabels" -}}
app: nationalparks
deployment: nationalparks
{{- end }}

{{/*
Database-specific labels.
*/}}
{{- define "parksmap.database.labels" -}}
{{ include "parksmap.labels" . }}
app: mongodb
app.kubernetes.io/name: mongodb
app.kubernetes.io/instance: mongodb
app.kubernetes.io/component: mongodb
role: database
{{- end }}

{{/*
Database selector labels.
*/}}
{{- define "parksmap.database.selectorLabels" -}}
app: mongodb
deployment: mongodb
{{- end }}

{{/*
Frontend image reference.
Uses digest if set, falls back to tag.
*/}}
{{- define "parksmap.frontend.image" -}}
{{- if .Values.frontend.image.digest -}}
{{ printf "%s@%s" .Values.frontend.image.repository .Values.frontend.image.digest }}
{{- else -}}
{{ printf "%s:%s" .Values.frontend.image.repository .Values.frontend.image.tag }}
{{- end }}
{{- end }}

{{/*
Backend image reference.
Uses digest if set, falls back to tag.
*/}}
{{- define "parksmap.backend.image" -}}
{{- if .Values.backend.image.digest -}}
{{ printf "%s@%s" .Values.backend.image.repository .Values.backend.image.digest }}
{{- else -}}
{{ printf "%s:%s" .Values.backend.image.repository .Values.backend.image.tag }}
{{- end }}
{{- end }}

{{/*
Database image reference.
Uses digest if set, falls back to tag.
*/}}
{{- define "parksmap.database.image" -}}
{{- if .Values.database.image.digest -}}
{{ printf "%s@%s" .Values.database.image.repository .Values.database.image.digest }}
{{- else -}}
{{ printf "%s:%s" .Values.database.image.repository .Values.database.image.tag }}
{{- end }}
{{- end }}

{{/*
Database image reference.
Uses digest if set, falls back to tag.
*/}}
{{- define "parksmap.databaseinit.image" -}}
{{- if .Values.databaseinit.image.digest -}}
{{ printf "%s@%s" .Values.databaseinit.image.repository .Values.databaseinit.image.digest }}
{{- else -}}
{{ printf "%s:%s" .Values.databaseinit.image.repository .Values.databaseinit.image.tag }}
{{- end }}
{{- end }}

{{/*
Database init image reference.
Uses digest if set, falls back to tag.
*/}}
{{- define "parksmap.databaseinit.image" -}}
{{- if .Values.databaseinit.image.digest -}}
{{ printf "%s@%s" .Values.databaseinit.image.repository .Values.databaseinit.image.digest }}
{{- else -}}
{{ printf "%s:%s" .Values.databaseinit.image.repository .Values.databaseinit.image.tag }}
{{- end }}
{{- end }}

{{/*
National Parks internal service URL
*/}}
{{- define "parksmap.backend.url" -}}
http://nationalparks.{{ include "parksmap.namespace" . }}.svc.cluster.local:{{ .Values.backend.port }}
{{- end }}
