{{- define "oilscope-rabbitmq.definitions" -}}
{{- $queueArgs := dict "x-queue-type" "quorum" "x-quorum-initial-group-size" 1 "x-max-length-bytes" .Values.queueMaxBytes "x-overflow" "reject-publish" -}}
{{- $main := merge (dict "x-delivery-limit" -1) $queueArgs -}}
{{- $retry := merge (dict "x-message-ttl" .Values.retryDelayMs) $queueArgs -}}
{{- $doc := dict
  "vhosts" (list (dict "name" .Values.vhost))
  "exchanges" (list (dict "name" .Values.exchange "vhost" .Values.vhost "type" "direct" "durable" true "auto_delete" false "internal" false "arguments" dict))
  "queues" (list
    (dict "name" .Values.queue "vhost" .Values.vhost "durable" true "auto_delete" false "arguments" $main)
    (dict "name" (printf "%s.retry" .Values.queue) "vhost" .Values.vhost "durable" true "auto_delete" false "arguments" $retry)
    (dict "name" (printf "%s.dead" .Values.queue) "vhost" .Values.vhost "durable" true "auto_delete" false "arguments" $queueArgs))
  "bindings" (list (dict "source" .Values.exchange "vhost" .Values.vhost "destination" .Values.queue "destination_type" "queue" "routing_key" .Values.routingKey "arguments" dict))
  "policies" (list (dict
    "name" "reliable-retry"
    "vhost" .Values.vhost
    "pattern" (printf "^%s\\.retry$" .Values.queue)
    "apply-to" "quorum_queues"
    "priority" 1
    "definition" (dict
      "dead-letter-strategy" "at-least-once"
      "overflow" "reject-publish"
      "dead-letter-exchange" .Values.exchange
      "dead-letter-routing-key" .Values.routingKey)))
-}}
{{ $doc | toPrettyJson }}
{{- end -}}
