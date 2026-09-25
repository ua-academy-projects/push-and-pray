# monitoring_agent

Installs the native VM agent for the selected cloud. It exports host CPU,
memory, and root filesystem usage at the configured interval and forwards
journald to CloudWatch Logs or Cloud Logging.

On the `infra` VM, the role also scrapes the local RabbitMQ and Redis
Prometheus endpoints. RabbitMQ provides its endpoint through the
`rabbitmq_prometheus` plugin; Redis uses the exporter declared in the shared
project configuration.

Terraform must first attach the monitoring permissions created by the matching
aws_monitoring or gcp_monitoring module.
