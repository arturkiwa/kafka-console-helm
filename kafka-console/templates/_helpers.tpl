{{- define "kc.name" -}}kafka-console{{- end -}}

{{- define "kc.labels" -}}
app.kubernetes.io/part-of: kafka-console
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/* image: repository@digest, or repository:tag (one of them is required) */}}
{{- define "kc.image" -}}
{{- if .digest -}}{{ .repository }}@{{ .digest }}
{{- else if .tag -}}{{ .repository }}:{{ .tag }}
{{- else -}}{{ fail (printf "image %s: set a digest or a tag" .repository) }}
{{- end -}}
{{- end -}}

{{/* restricted Pod Security: non-root, no privilege escalation, no capabilities, read-only root, seccomp */}}
{{- define "kc.containerSecurity" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}
