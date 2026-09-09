# Cloud monitoring: manual setup and implementation plan

Status: planning only. No cloud resources have been changed by this task.
Start with the manual AWS steps below. Implement Terraform only after the manual setup is verified and implementation is requested.

## Requirements and agreed decisions

| Task | Manual first | Later implementation |
| --- | --- | --- |
| 1. Base EC2 metrics | Inspect built-in CloudWatch metrics; optionally enable detailed monitoring | Per-instance detailed monitoring option |
| 2. Native agents on EC2 | Install Amazon CloudWatch Agent | Shared agent configuration and installation assets |
| 3. Cloud-aware agents | AWS uses CloudWatch Agent; GCP uses Ops Agent | Select according to each VM's effective cloud |
| 4. HTTP 500 alerts | Traefik access logs → CloudWatch Logs → metric filter → alarm | Equivalent logging and alert resources for each cloud |
| 5. AWS budget email alerts | Monthly $100 budget, alerts at $50 and $100 | User supplies recipient email |
| 6. Budgets in both clouds | AWS first | AWS account budget; GCP project budget; same thresholds |
| 7. AWS dashboard | Create in CloudWatch console | Verify useful charts before encoding |
| 8. Dashboards in both clouds | AWS first | CloudWatch dashboard and Cloud Monitoring dashboard |
| 9. Synthetic tests | Scheduled public HTTPS health check | AWS Synthetics and GCP uptime checks; journey tests separately |
| 10. Operational alerts | Availability, CPU, memory, disk, missing telemetry | Matching policies, notifications, and runbooks |

Email addresses will be entered by the operator. Both clouds should notify at **$50 and $100 of actual monthly spend**, not use separate cloud-specific budgets. Use a $100 monthly budget with 50% and 100% thresholds. Budgets notify; they do not cap spending or stop resources. Billing data and notifications are delayed.

## Project-specific findings

- Cloud infrastructure root: `infrastructure/terraform`; AWS and GCP modules are under `modules/aws` and `modules/gcp`.
- Each VM resolves its cloud from `vm.cloud`, falling back to `default_cloud`.
- Roles are bastion, database, history, fetcher, and UI. Monitor every VM, including the bastion.
- The UI VM runs Traefik directly on port 443. There is no application load balancer in the inspected configuration, so ALB HTTP error metrics are not available.
- The proxy Compose template is `../ansible/oilscope/platform/roles/compose_project/templates/compose.proxy.yaml.j2`. It currently has no access-log configuration.
- The edge proxy's default deployed Compose path is `/opt/oilscope/proxy/compose.yaml`. Confirm the actual deployment path before editing a running VM.
- The UI `/health` endpoint checks History connectivity and PostgreSQL session persistence. It can return 503; an exact-500 alarm alone would miss that outage.
- Built-in EC2 monitoring does not provide guest memory utilization or filesystem fullness. Those require the agent.
- Existing AWS instances have individual IAM roles and instance profiles. Add agent permissions to those roles; do not replace their existing permissions.
- GCP instances have individual service accounts and `cloud-platform` access scopes. Agent IAM permissions must still be added.
- The example image is Ubuntu 26.04. Verify the actual OS and architecture on each VM and check current agent support before installation.

## Manual AWS setup

### 1. Identify the target resources

1. Sign in to the AWS account used by the project and select the EC2 region from the project configuration.
2. In **EC2 → Instances**, record each VM's Name, instance ID, role, and IAM role.
3. Record the UI public hostname from `vms.ui.public_endpoint.hostname`.
4. Connect to each VM using the existing SSH configuration/bastion. Private VMs need outbound HTTPS through NAT or suitable VPC endpoints for telemetry, plus access to package download locations.
5. On each VM, inspect `/etc/os-release` and run `uname -m` to identify the OS and architecture.

Do not open monitoring ports to the internet. Both native agents send telemetry outbound.

### 2. Inspect base EC2 metrics

1. Open an instance's **Monitoring** tab, or **CloudWatch → Metrics → All metrics → EC2 → Per-Instance Metrics**.
2. Select CPUUtilization, NetworkIn, NetworkOut, StatusCheckFailed, StatusCheckFailed_Instance, and StatusCheckFailed_System.
3. For burstable T-family instances, also inspect CPUCreditBalance and the applicable surplus-credit metrics. For attached EBS storage, inspect volume read/write and latency/queue metrics in the EBS namespace as applicable.
4. For one-minute EC2 performance metrics, use **EC2 → Actions → Monitor and troubleshoot → Manage detailed monitoring** and enable it. Basic monitoring generally reports at five-minute intervals; EC2 status checks have their own one-minute cadence.
5. Use five-minute periods for CPU alarms until detailed monitoring is enabled. Confirm fresh timestamps, not just historical charts.

Detailed monitoring, custom metrics, logs, alarms, dashboards, and synthetic runs can incur charges. Start with a small metric set and five-minute synthetic runs.

### 3. Set up operational email notifications

1. In the same region, open **SNS → Topics → Create topic**.
2. Choose **Standard**, name it `<prefix>-<environment>-monitoring`, and create it.
3. Create an **Email** subscription with your chosen address.
4. Open the subscription confirmation email and confirm it.
5. Verify that the subscription is confirmed. Select this topic when creating CloudWatch alarms.

Budget emails are configured separately in AWS Budgets; they do not require this SNS topic when using direct email recipients.

### 4. Install CloudWatch Agent manually on every EC2 VM

1. Open **IAM → Roles → the instance's existing role → Add permissions → Attach policies**.
2. Attach AWS-managed `CloudWatchAgentServerPolicy` for the manual trial. Keep the role's existing secret and registry permissions. Later implementation should review whether a narrower policy is practical.
3. On the VM, download and install the official package. For Ubuntu x86-64:

   ```sh
   curl -fSL --retry 5 \
     https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
     -o /tmp/amazon-cloudwatch-agent.deb
   sudo dpkg -i /tmp/amazon-cloudwatch-agent.deb
   ```

   For Ubuntu ARM64 use the official `ubuntu/arm64/latest/` package URL instead. Use the vendor's signature verification procedure where required by your installation policy.

4. Create `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json` on the VM with the following configuration:

   ```json
   {
     "agent": { "metrics_collection_interval": 60 },
     "metrics": {
       "namespace": "CWAgent",
       "append_dimensions": { "InstanceId": "${aws:InstanceId}" },
       "metrics_collected": {
         "mem": { "measurement": ["mem_used_percent"] },
         "disk": {
           "measurement": ["used_percent"],
           "resources": ["/"],
           "drop_device": true
         }
       }
     }
   }
   ```

   Preserve `${aws:InstanceId}` literally. Do not let a shell expand it when creating the JSON. Add other actual filesystem mount paths if application data is on separate volumes.

5. Start the agent with that configuration:

   ```sh
   sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
     -a fetch-config -m ec2 \
     -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
   sudo systemctl enable amazon-cloudwatch-agent
   sudo systemctl status amazon-cloudwatch-agent --no-pager
   ```

6. In **CloudWatch → Metrics → CWAgent**, find `mem_used_percent` and `disk_used_percent` for that instance. Allow several minutes for initial ingestion.
7. Select the complete dimension set actually published. Disk series also include filesystem dimensions such as `path` and `fstype`; an alarm using only InstanceId will not match that series.
8. If metrics are missing, inspect `/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log`, the VM role, outbound connectivity, and the selected AWS region.

### 5. Collect Traefik access logs on the UI VM

This is a manual change on the deployed UI VM, not a repository change. Back up the deployed Compose file first. A later Ansible deployment may overwrite it until the template is updated in the implementation phase.

1. Create a host directory with permissions allowing the proxy to write and the agent to read:

   ```sh
   sudo install -d -m 0750 /var/log/oilscope
   ```

2. Add these arguments under the deployed Traefik service's `command`:

   ```yaml
   - "--accesslog=true"
   - "--accesslog.format=json"
   - "--accesslog.filepath=/var/log/oilscope/traefik-access.log"
   - "--accesslog.fields.defaultmode=drop"
   - "--accesslog.fields.names.StartUTC=keep"
   - "--accesslog.fields.names.DownstreamStatus=keep"
   - "--accesslog.fields.names.Duration=keep"
   - "--accesslog.fields.headers.defaultmode=drop"
   ```

   Add the volume mapping `/var/log/oilscope:/var/log/oilscope` under that service's `volumes`. Keeping only these fields avoids collecting authorization headers, cookies, and query strings for this status-count use case.

3. Validate the deployed Compose file and recreate only Traefik using the same Compose file and project name as the deployment. Schedule the brief proxy restart appropriately. Confirm HTTPS still works.
4. Request `https://<UI_HOSTNAME>/health` and check that the log contains JSON with a numeric `DownstreamStatus`.
5. In **CloudWatch → Logs → Log groups**, create `/<prefix>/<environment>/traefik` and set a seven-day retention period for the trial.
6. Add this top-level `logs` section to the agent JSON on the UI VM, alongside `agent` and `metrics`, replacing the log group placeholder:

   ```json
   "logs": {
     "logs_collected": {
       "files": {
         "collect_list": [{
           "file_path": "/var/log/oilscope/traefik-access.log",
           "log_group_name": "/<prefix>/<environment>/traefik",
           "log_stream_name": "{instance_id}"
         }]
       }
     }
   }
   ```

7. Repeat the agent `fetch-config` command from step 4 to load the updated JSON. Confirm new events appear in the log group.
8. Configure host log rotation before leaving the setup running. Use bounded size/retention and verify the writer reopens the rotated file; plan a tested Traefik-supported reopen procedure. CloudWatch retention does not limit the source file on the VM. Avoid an unbounded file on the small root disks.

These logs measure responses passing through the UI proxy. They do not cover requests sent directly to private services.

### 6. Create HTTP 500 and 5xx alarms

1. Open the access log group and choose **Metric filters → Create metric filter**.
2. For exact HTTP 500 responses use `{ $.DownstreamStatus = 500 }`.
3. Test with `{"DownstreamStatus":500}` and `{"DownstreamStatus":200}` in the console filter tester. Only the first should match.
4. Set namespace `OilScope/HTTP`, metric name `HTTP500Count`, metric value `1`, and default value `0`. Do not add dimensions for this initial aggregate metric.
5. Create a metric alarm using **Sum**, period **5 minutes**, threshold **>= 1**, and **1 of 1** datapoints. Select the confirmed SNS topic.
6. Treat missing data as **not breaching** for this event-count alarm. Missing logs are not proof of healthy operation; use a separate synthetic availability alarm.
7. Add a second filter `{ $.DownstreamStatus >= 500 && $.DownstreamStatus < 600 }` with metric name `HTTP5xxCount`. This includes the UI's 503 health failures and proxy 502/504 failures. Initially notify for >= 1 in five minutes, then tune based on observed traffic.
8. Metric filters process new matching events, not old log history. A filter test does not publish a metric or prove delivery of an alarm email.

For end-to-end validation, use a controlled test environment or an explicitly identified synthetic log stream in this group to publish one test 500 event, then verify the metric, alarm transition, and email. Separately verify real proxy responses reach the group. Do not deliberately break the production application merely to produce an error.

### 7. Create CPU, memory, disk, and availability alarms

Create alarms per VM; do not average all VMs together, which can hide a single failing host.

| Signal | Initial condition | Period and evaluation | Missing data |
| --- | --- | --- | --- |
| EC2 CPUUtilization | Average >= 80% | 5 minutes, 2 of 2 | Missing; use availability checks separately |
| CWAgent mem_used_percent | Average >= 85% | 5 minutes, 2 of 2 | Missing; add missing-agent detection |
| CWAgent disk_used_percent | Maximum >= 85% on each monitored filesystem | 5 minutes, 2 of 2 | Missing; add missing-agent detection |
| EC2 StatusCheckFailed | Maximum >= 1 | 1 minute, 2 of 2 | Breaching for an always-on VM |
| Agent heartbeat proxy | mem_used_percent < 0 (normally impossible) | 5 minutes, 2 of 2 | Breaching, so absent agent metrics trigger it |
| Synthetic SuccessPercent | Average < 100 | 5 minutes, 2 of 2 | Breaching for an enabled canary |

Send ALARM notifications to SNS; enable OK notifications for recovery if desired. Pause/adjust alarms during intentional maintenance. The missing-agent alarm also fires for stopped VMs; that is intentional for always-on workloads.

EC2 status checks measure infrastructure health. A passing EC2 status check does not mean Docker, the application, or the database is healthy. Use the public health synthetic check for the user-facing dependency path and inspect individual service/container health during diagnosis. Add private service probes later without exposing database or service ports publicly.

### 8. Create the AWS budget

1. Open **Billing and Cost Management → Budgets → Create budget**.
2. Choose a customized **Cost budget**, recurring **Monthly**, fixed amount **100 USD**.
3. For the first budget, include the whole AWS account and all services so NAT, EBS, public IPv4, and monitoring costs are included. Do not filter only to EC2.
4. Add an **Actual** spending notification at **50%** ($50), with your email address.
5. Add another **Actual** spending notification at **100%** ($100), with the same address.
6. Optionally add a separate forecasted 100% notification; retain both actual thresholds.
7. Review and create the budget. Check the scope and email address. Do not configure automatic shutdown actions.

Budget alerts are threshold notifications based on delayed billing updates, not immediate transactions. Do not spend money just to test them. If moving this budget under Terraform later, import it rather than creating a duplicate.

### 9. Create synthetic tests

1. Open **CloudWatch → Application Signals / Synthetics Canaries → Create canary** (navigation wording can vary).
2. Select a heartbeat or API monitoring blueprint for `https://<UI_HOSTNAME>/health`.
3. Use a currently supported runtime offered by the console. Start with a **five-minute** schedule, a **10–30 second** timeout, and a clear name such as `<prefix>-<environment>-health`.
4. Require HTTP 200. Where the blueprint permits response validation, also assert JSON values `status = ok`, `history = connected`, and `sessions = postgresql`.
5. Use public execution for this publicly reachable HTTPS endpoint. Let the console create the required canary execution role and artifact bucket, then review their permissions and retention. Keep screenshots/artifacts private and retain only a short troubleshooting window.
6. Run it once and inspect results. Create the SuccessPercent alarm described above. Chart Duration as well; add a latency alarm after establishing a normal baseline.
7. Verify a controlled failure and recovery in a test environment. Confirm that TLS/DNS/connection failures count as failed runs.

A `/health` check is a synthetic API test, not a browser journey. In a second stage, add a browser canary that loads the UI and verifies a stable visible element. A price-history read test can exercise a real read path. Use a dedicated test account if authentication becomes necessary; keep credentials out of code and artifacts. Fetcher freshness and private service checks need separate signals.

### 10. Create the AWS dashboard

In **CloudWatch → Dashboards → Create dashboard**, use `<prefix>-<environment>-operations` and add:

- CPU per instance; memory per instance; root filesystem usage per instance.
- EC2 status checks and an alarm-status widget.
- NetworkIn/NetworkOut and CPUCreditBalance for applicable instances.
- HTTP500Count and HTTP5xxCount as summed counts.
- Canary SuccessPercent and Duration.
- A text widget with the service hostname, region, VM-role mapping, and troubleshooting notes.

Choose metrics with the exact same dimensions as their alarms. Use a three-hour default view and five-minute periods. Confirm recent datapoints for every expected VM. Link to AWS Budgets for spending; the operational dashboard is not a substitute for budget notifications.

## Manual GCP reference, after AWS validation

1. Enable Cloud Monitoring and Cloud Logging APIs in the project.
2. Add `roles/monitoring.metricWriter` and `roles/logging.logWriter` to each VM's existing service account. Preserve existing permissions and verify the instance has appropriate OAuth access scopes.
3. On a supported Ubuntu VM, download `https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh` and run the saved script with `sudo bash <script> --also-install`.
4. Check `sudo systemctl status google-cloud-ops-agent`. Built-in host metrics should become visible in Metrics Explorer.
5. For Traefik, configure an Ops Agent files receiver for `/var/log/oilscope/traefik-access.log` plus a `parse_json` processor in `/etc/google-cloud-ops-agent/config.yaml`; attach them to a logging pipeline and restart the agent. Preserve existing configuration. Verify `jsonPayload.DownstreamStatus` in Logs Explorer.
6. Create an email notification channel in Monitoring, then CPU, memory, filesystem, metric-absence, and HTTPS uptime policies. Verify the scale of each metric: Compute CPU utilization is a fraction, while agent percentage metrics use percent units.
7. Create a log-based counter scoped to the UI instance/log for `jsonPayload.DownstreamStatus=500`, and another for the 500–599 range.
8. Use a public HTTPS uptime check for `/health`, with response/content checks where supported. Alert on persistent failure across checker locations; do not count a single checker failure as a global outage.
9. In Cloud Billing, create a $100 monthly budget scoped to this project, with current-spend thresholds 50% and 100%. Select the email notification channel. The budget currency must match the billing account currency; if the account is not billed in USD, resolve that before claiming exact dollar thresholds.
10. Build a Cloud Monitoring dashboard with the same operational signals as AWS.

The Ops Agent is for GCP VMs; do not install it on EC2 as a substitute for CloudWatch Agent.

## Detailed later implementation plan — no implementation authorized yet

### Phase A: configuration contract

- Add an optional `monitoring` configuration section and update `project-config.schema.json` plus the example config together.
- Separate enable switches for agents, alerts, dashboards, synthetics, and budgets. Existing configurations must keep their current behavior when the section is absent.
- Include operator-supplied email recipients, log retention, collection interval, alarm thresholds/durations, endpoint hostname/path, and synthetic schedule.
- Configure each cloud's monthly amount as 100 USD and actual thresholds as `[0.5, 1.0]`. Keep AWS account scope explicit and GCP project scope explicit.
- Include the GCP billing account ID and require a USD billing account for exact dollar thresholds. Do not put credentials in this config.
- Validate that enabled email alerts have recipients, enabled GCP budgets have billing information, and enabled synthetics have a valid endpoint. Email is intentionally not supplied yet.

### Phase B: cloud-aware agents and permissions

- Determine the effective cloud per VM using the existing override/default logic. Reuse the resolved maps in the existing cloud VM modules.
- Add AWS detailed monitoring only when enabled. Add CloudWatch permissions to the existing instance roles.
- Add GCP metric-writer/log-writer IAM grants and API enablement dependencies without replacing existing service-account permissions.
- Define one reviewed agent configuration per cloud, shared by documented manual installation and automatic bootstrap.
- Preserve AWS SSH cloud-init by merging installation commands/files with the existing SSH user configuration, rather than replacing it.
- On GCP, wire an idempotent installation mechanism into VM startup metadata or the chosen supported agent policy mechanism. Preserve SSH metadata.
- Explicitly solve rollout to existing VMs: AWS user data normally runs only on first boot. Changing it is not an in-place agent deployment strategy and may stop/start instances. Document manual installation for existing hosts or implement a separately reviewed remote-management rollout. Do not replace VMs merely to install agents.
- Make startup retries and installation errors observable. Verify IAM/API/network readiness, architecture selection, supported OS versions, and behavior after reboot.

### Phase C: access logging

- Extend the actual Traefik Compose template and deployment tasks to create the host log directory, bind-mount it, and emit the minimal JSON fields used by alerts.
- Add tested log rotation with bounded source-file storage. Preserve file ownership and verify collection across rotation/restarts.
- Create dedicated CloudWatch log groups with retention; configure Ops Agent structured collection and appropriate GCP retention.
- Ensure Terraform alarm dimensions match the agent's emitted dimensions exactly; decide explicitly whether to retain filesystem dimensions or publish aggregate series.
- Test both exact-500 and all-5xx filters using matching/nonmatching fixtures and a controlled end-to-end log event.

### Phase D: AWS monitoring resources

- Add a dedicated AWS monitoring module receiving effective AWS VMs, instance IDs, region, notification settings, and endpoint settings.
- Extend VM outputs with instance IDs if needed; keep outputs backward compatible.
- Create SNS topic/subscriptions, log metric filters, per-instance CPU/memory/disk/status/missing-agent alarms, and HTTP alarms.
- Create the CloudWatch dashboard from the same metric definitions used for alarms to avoid dimension drift.
- Create the AWS monthly budget with direct email subscribers at 50% and 100%. Keep the budget independent of monitoring-region assumptions.
- Create Synthetics canary packaging, IAM execution role, private artifact storage, log/artifact retention, schedule, and success/latency alarms. Verify the chosen current runtime and artifact structure before coding.
- Document the human SNS email confirmation step; Terraform cannot click the confirmation link.

### Phase E: GCP monitoring resources

- Add a GCP monitoring module receiving project details, GCE instance IDs/zones, notification settings, and billing configuration.
- Enable required APIs with safe deletion behavior. Add email notification channels, log-based metrics, and per-VM policies for CPU/memory/disk/missing telemetry.
- Create HTTPS uptime checks and availability policies with deliberate multi-location aggregation and missing-data behavior.
- Add a Cloud Monitoring dashboard with appropriate metric filters, aligners, units, and instance labels.
- Create a project-scoped `google_billing_budget` with 50% and 100% current-spend thresholds and the operator's email channels. Confirm billing permissions and quota-project requirements for the chosen authentication method.
- Use public uptime checks for basic synthetic API coverage. If browser journeys are required on both clouds, define that separately; GCP uptime checks are not browser journeys.

### Phase F: transition and verification

1. Inventory the manually created resources and choose which to import. Record actual resource IDs and names.
2. Use Terraform import for supported resources; avoid duplicate budgets, dashboards, and notifications. Review ownership of existing agent configuration and IAM grants.
3. Run formatting, configuration/schema validation, and Terraform validation with the pinned providers.
4. Review plans for disabled monitoring, AWS-only, GCP-only, and mixed-cloud VM configurations. A disabled optional feature must not create its resources.
5. Verify plans do not replace VMs, erase SSH metadata, remove runtime permissions, or unexpectedly create resources in the other cloud.
6. In a test environment, verify fresh metrics, structured logs, exact dimensions, synthetic success, controlled alarm failure/recovery, email delivery, and log rotation.
7. Check agent persistence after reboot and ensure Ansible deployment preserves monitoring configuration.
8. Apply only after implementation is requested and the concrete plan is reviewed. Keep manual resources active until replacements/imports are verified.

## Acceptance checklist

- Every expected VM has current base metrics and agent memory/filesystem metrics.
- Both native agents use instance identities rather than static credentials.
- A controlled 500 event produces the intended metric/alarm/email; a 200 does not.
- HTTP 503 and synthetic connectivity failures are also detected.
- CPU, memory, disk, infrastructure availability, and missing-agent alerts can be diagnosed by VM.
- Email confirmation and recovery notifications are tested where applicable.
- Each cloud has actual monthly spend notifications at $50 and $100; scope and currency are documented.
- Dashboards show real current data for each role.
- Source logs and cloud artifacts have bounded retention.
- Terraform migration preserves VM identity, SSH access, and existing application deployment.

## Official references

- [EC2 monitoring](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-cloudwatch.html)
- [CloudWatch Agent installation packages](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/download-CloudWatch-Agent-on-EC2-Instance-commandline-first.html)
- [CloudWatch Agent configuration](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html)
- [Supported CloudWatch Agent operating systems](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/supported-operating-systems.html)
- [Traefik access logs](https://doc.traefik.io/traefik/observability/access-logs/)
- [CloudWatch Logs JSON filter syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/matching-terms-json-log-events.html)
- [AWS cost budget creation](https://docs.aws.amazon.com/cost-management/latest/userguide/create-cost-budget.html)
- [AWS Synthetics creation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Synthetics_Canaries_Create.html)
- [GCP Ops Agent support](https://docs.cloud.google.com/stackdriver/docs/solutions/agents/ops-agent)
- [GCP Ops Agent configuration](https://docs.cloud.google.com/logging/docs/agent/ops-agent/configuration)
- [Terraform AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform GCP budget resource](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/billing_budget)
- [Terraform GCP alert policies](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy)
- [Terraform GCP uptime checks](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_uptime_check_config)
