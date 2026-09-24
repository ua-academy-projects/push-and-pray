# application_monitoring

Installs the standalone Python workload collector and its systemd timer after
service deployment. Reads non-secret configuration from `project_config_path`
and the cloud's `collector_configurations` in `terraform_outputs_path`.
Bastion is excluded. When disabled, a previously installed collector is stopped.

AWS and Azure centralized Docker logs use per-service symlinks updated after
deployment; GCP's Ops Agent reads the Docker JSON files directly and needs
none. On Azure the collector writes one flat JSON object per measurement -
`{Timestamp, VMKey, Role, Metric, Value}` - which the Azure Monitor Agent
ingests into the `OilscopeMetrics_CL` table, because Azure has no per-VM
custom metric namespace to publish into. Those column names are the data
collection rule's declared stream: nested records will not ingest.
The collector uses the Docker socket for local diagnostics and the existing VM
identity for cloud publication; it does not store application/cloud credentials.
See the repository's `docs/monitoring.md` for metrics and rollout instructions.
