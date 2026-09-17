# application_monitoring

Installs the standalone Python workload collector and its systemd timer after
service deployment. Reads non-secret configuration from `project_config_path`
and the cloud's `collector_configurations` in `terraform_outputs_path`.
Bastion is excluded. When disabled, a previously installed collector is stopped.

AWS centralized Docker logs use per-service symlinks updated after deployment.
The collector uses the Docker socket for local diagnostics and the existing VM
identity for cloud publication; it does not store application/cloud credentials.
See the repository's `docs/monitoring.md` for metrics and rollout instructions.
