# Google Cloud Ops Agent role

Installs the Google Cloud Ops Agent on Debian-family GCP VMs and ensures its
systemd service is enabled and running. The built-in agent configuration sends
host metrics and syslog to Cloud Monitoring and Cloud Logging.

The VM service account must have `roles/monitoring.metricWriter` and
`roles/logging.logWriter`. Terraform grants both roles in the `iam` module.
