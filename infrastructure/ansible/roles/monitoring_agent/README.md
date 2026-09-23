# monitoring_agent

Installs the native VM agent for the selected cloud. It exports host CPU,
memory, and root filesystem usage at the configured interval and forwards
journald to CloudWatch Logs or Cloud Logging.

Terraform must first attach the monitoring permissions created by the matching
aws_monitoring or gcp_monitoring module.
