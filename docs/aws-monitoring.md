# AWS monitoring

## Resources

- Dashboard: `oilscope-dev-aws` in `eu-west-1`.
- SNS topic: `oilscope-dev-alerts` in `eu-west-1`.
- Application log group: `/oilscope-dev/application`, retained for 14 days.
- Synthetic canary: `oilscope-dev-api`, every 5 minutes.
- Monthly budget: `oilscope-dev-monthly`, USD 20.

Every operational alarm sends to the same SNS topic through both
`alarm_actions` and `ok_actions`. `ALARM` is the kickoff notification and `OK`
is the closure notification.

## Dashboard metrics

- EC2 status, instance status, and system status checks.
- CPU utilization and T-series CPU credit balance.
- Memory and root disk usage from CloudWatch Agent.
- Network input and output.
- EBS root-volume throughput and queue length.
- Application HTTP 5xx count and recent error logs.
- Synthetic success, failures, and duration.
- CloudWatch Logs incoming events and bytes.

## Alert thresholds

- EC2 status check: `>= 1` for 2 minutes.
- CPU: `> 80%` for 5 minutes.
- Memory: `> 80%` for 5 minutes.
- Root disk: `> 80%` for 10 minutes.
- HTTP 5xx: `>= 1` in 5 minutes.
- Synthetic: success below 100% for 2 consecutive runs.

## Controlled tests

CPU on one dev VM:

```bash
stress-ng --cpu 2 --timeout 10m
```

Memory on one dev VM:

```bash
stress-ng --vm 1 --vm-bytes 85% --timeout 10m
```

Structured HTTP 5xx pipeline event without stopping the application:

```bash
sudo sh -c 'printf "%s\n" \
  '\''{"timestamp":"2026-01-01T00:00:00Z","service":"ui","event":"http_access","method":"GET","route":"/monitoring-test","status":500,"duration_ms":1,"request_id":"monitoring-test"}'\'' \
  >> /var/log/oilscope/monitoring-test.jsonl'
```

This validates agent ingestion, JSON field parsing, the metric and alarm. It
does not prove that a real application failure path was exercised. Remove the
test file afterwards.

For every test, record the dashboard graph, `ALARM` email, recovery graph, and
`OK` email. Never fill the production root filesystem to test a disk alarm.

## Apply

```bash
AWS_PROFILE=oilscope-deploy \
AWS_REGION=eu-west-1 \
AWS_DEFAULT_REGION=eu-west-1 \
terraform -chdir=infrastructure/terraform apply \
  -var="project_config_path=$(pwd)/project-config.json"
```

Install or update agents after the Terraform IAM and log-group resources exist:

```bash
export AWS_PROFILE=oilscope-deploy
export AWS_REGION=eu-west-1
export AWS_DEFAULT_REGION=eu-west-1
export OILSCOPE_PROJECT_CONFIG="$(pwd)/project-config.json"
export OILSCOPE_AWS_SSH_KEY="${HOME}/.ssh/id_ed25519"

.oilscope-deploy/venv/bin/ansible-playbook \
  oilscope.platform.monitoring \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e "project_config_path=$(pwd)/project-config.json"
```
