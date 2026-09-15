# VM deployment operations

Current workload configuration is owned by the
`oilscope.platform.deploy_workloads` Ansible playbook. Terraform provisions the selected
AWS or GCP VMs; it does not install an application-wide cloud-init deployment service.
Run operational commands over private SSH through the single bastion.

Each workload VM has `/opt/oilscope/app/compose.yaml` and exactly its assigned runtime:

- database/infra: `postgres` and `redis` in `self_hosted`, or `rabbitmq` and `redis` in
  `managed`; the `migrate` service is a one-shot job in both modes;
- history: `history`;
- fetcher: `fetcher`;
- UI: `ui`, plus Traefik in `/opt/oilscope/proxy`.

Inspect the application on a workload VM:

```sh
docker compose --project-name petroscope \
  --file /opt/oilscope/app/compose.yaml ps
docker compose --project-name petroscope \
  --file /opt/oilscope/app/compose.yaml logs --tail=200 <service>
```

For Traefik on UI, use project `oilscope-proxy` and
`/opt/oilscope/proxy/compose.yaml`. Traefik's JSON access log is also written to
`/var/log/oilscope/traefik/access.log` and shipped to CloudWatch Logs or Cloud Logging
when HTTP 5xx monitoring is enabled.

Redeploy by rerunning the relevant Ansible playbook with the same canonical config path;
do not hand-create replacement environment files:

```sh
ansible-playbook oilscope.platform.ui \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

Compose reconciliation and health checks are idempotent. Runtime confirmation of a
minimal-change second Ansible run belongs to the deployment testing phase.
