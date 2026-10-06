{{- define "oilscope.labels" -}}
app.kubernetes.io/name: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- end -}}

{{- define "oilscope.selector" -}}
app.kubernetes.io/name: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "oilscope.brokerEnv" -}}
- name: RABBITMQ_EXCHANGE
  value: {{ .Values.broker.exchange | quote }}
- name: RABBITMQ_ROUTING_KEY
  value: {{ .Values.broker.routingKey | quote }}
- name: RABBITMQ_QUEUE
  value: {{ .Values.broker.queue | quote }}
- name: RABBITMQ_TIMEOUT_SECONDS
  value: {{ .Values.broker.timeoutSeconds | int64 | quote }}
- name: RABBITMQ_RECONNECT_SECONDS
  value: {{ .Values.broker.reconnectSeconds | int64 | quote }}
- name: RABBITMQ_MAX_ATTEMPTS
  value: {{ .Values.broker.maxAttempts | int64 | quote }}
- name: OUTBOX_POLL_SECONDS
  value: {{ .Values.broker.outboxPollSeconds | int64 | quote }}
- name: OUTBOX_BATCH_SIZE
  value: {{ .Values.broker.outboxBatchSize | int64 | quote }}
- name: RABBITMQ_CA_FILE
  value: {{ printf "%s/ca.crt" .Values.broker.caPath | quote }}
{{- end -}}

{{- define "oilscope.spread" -}}
- maxSkew: 1
  topologyKey: kubernetes.io/hostname
  whenUnsatisfiable: ScheduleAnyway
  labelSelector:
    matchLabels:
      app.kubernetes.io/name: {{ .root.Release.Name }}
      app.kubernetes.io/component: {{ .component }}
{{- end -}}
