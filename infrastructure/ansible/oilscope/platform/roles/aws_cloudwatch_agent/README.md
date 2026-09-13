# AWS CloudWatch Agent

Installs the unified Amazon CloudWatch Agent on existing AWS EC2 instances.
The role publishes memory and root-filesystem metrics that EC2 does not provide
natively to the `OilScope` namespace. It sends `/var/log/syslog` from every
instance and Docker JSON logs from workload instances to CloudWatch Logs. EC2
provides availability, CPU, network, and EBS metrics without this role.
Terraform uses the collected Traefik access records for request and HTTP 5xx
metric filters.

The role does not restart application containers. It applies only the agent
configuration and ensures that the agent service is enabled and running.

## Requirements

- Run only on members of the dynamic inventory's `aws` group.
- Use the AMD64 Ubuntu images configured by this project.
- VMs require outbound HTTPS access to the regional AWS endpoints and the
  CloudWatch Agent package bucket.
- The attached EC2 role must have `CloudWatchAgentServerPolicy`. The Terraform
  `aws-observability` module attaches this policy.

## Variables

- `aws_cloudwatch_agent_metrics_namespace`: custom metric namespace; defaults
  to `OilScope`.
- `aws_cloudwatch_agent_metrics_interval`: collection interval in seconds;
  defaults to `60`.
- `aws_cloudwatch_agent_collect_docker_logs`: whether to collect Docker JSON
  logs; defaults to true for hosts in the `workloads` group.
- The remaining defaults expose package, service, configuration, log-group,
  and control-command settings.

## Run

```bash
ansible-playbook oilscope.platform.configure_aws_observability \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The playbook is idempotent and can be run against existing EC2 instances.
Terraform creates the CloudWatch log groups and manages their retention before
the agent starts writing to them.

## License

GPL-2.0-or-later
