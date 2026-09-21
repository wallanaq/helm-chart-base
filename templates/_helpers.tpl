{{/*
Expand the name of the chart.
*/}}
{{- define "base-webapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "base-webapp.fullname" -}}
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
{{- define "base-webapp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "base-webapp.labels" -}}
helm.sh/chart: {{ include "base-webapp.chart" . }}
{{ include "base-webapp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "base-webapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "base-webapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "base-webapp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "base-webapp.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Shared Pod spec (i.e. the contents of spec.template.spec), used by both
templates/deployment.yaml (rollout.enabled: false) and templates/rollout.yaml
(rollout.enabled: true). Deployment and Rollout need byte-identical Pod
configuration -- containers, env/envFrom, probes, resources, volumes -- so
this is the single source of truth for that shape, rather than maintaining
two copies that can quietly drift apart.

Callers include this immediately under their own "spec:" key at
spec.template.spec and pipe it through "nindent 6" -- both call sites sit at
the same nesting depth (spec.template.spec), so the same indent works for
both. See templates/deployment.yaml and templates/rollout.yaml.
*/}}
{{- define "base-webapp.podSpec" -}}
{{- with .Values.imagePullSecrets -}}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{ end -}}
serviceAccountName: {{ include "base-webapp.serviceAccountName" . }}
{{- with .Values.podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
containers:
  - name: {{ .Chart.Name }}
    {{- with .Values.securityContext }}
    securityContext:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
    imagePullPolicy: {{ .Values.image.pullPolicy }}
    ports:
      - name: http
        containerPort: {{ .Values.service.port }}
        protocol: TCP
    {{- if .Values.secretName }}
    envFrom:
      - secretRef:
          name: {{ .Values.secretName }}
    {{- end }}
    {{- if or .Values.podInfo.enabled .Values.env }}
    env:
      {{- if .Values.podInfo.enabled }}
      - name: POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      {{- end }}
      {{- with .Values.env }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
    {{- end }}
    {{- with .Values.livenessProbe }}
    livenessProbe:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.readinessProbe }}
    readinessProbe:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.volumeMounts }}
    volumeMounts:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- with .Values.volumes }}
volumes:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
