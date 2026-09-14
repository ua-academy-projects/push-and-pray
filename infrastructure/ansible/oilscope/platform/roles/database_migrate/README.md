# Managed database migrations

The `migrate` playbook initializes the selected managed database from the first
History inventory host, before History starts in `deploy_workloads`. Application
mode skips this play and keeps the existing database-VM migration flow. To run
it independently, use `oilscope.platform.migrate` with the usual inventory,
`project_config_path`, and refreshed `terraform_outputs_path`. Include the first
History host in the invocation's limit. Run migrations before starting services;
this is not an online database-switch workflow.

The play includes its fresh-host prerequisites: baseline setup, Docker,
database connection/CA resolution, workload-secret resolution, and registry
login. It uses the configured database image tag, which must contain the current
migration files and runner. Build/publish that image before deployment.

The controller retrieves secrets with its existing operator identity: AWS CLI
`secretsmanager get-secret-value`, or `gcloud secrets versions access`. The
operator must have read access to the exported administrator secret and the
POSTGRES_PASSWORD secrets of the Fetcher/History VMs — UI has no PostgreSQL
credential of its own since its session store moved to Redis. AWS KMS
decryption permission is also needed if those secrets use a customer-managed
key. No new administrator-secret permissions are granted to workload VM
identities. The migration host still resolves its normal registry/workload
secrets as before.

Administrator credentials are passed through the environment of short-lived
Docker containers over the SSH deployment connection. Secret-handling tasks
use `no_log`; the role writes no password into its Compose or SQL files and
clears its credential facts in an always block. Host root/Docker administrators
can inspect a running container's environment. This is not a separate hardened
migration host or protection against a compromised History VM.

Migration files live separately at `/opt/oilscope/migrate/compose.yaml`, with
project name `oilscope-migrate`; History's Compose file is never overwritten.
The CA directory is mounted read-only, and every connection uses `verify-full`.
The sequence is:

1. Read the administrator secret and pull the configured image.
2. Create `oil_tracker_<vm-key>` logins with existing workload password secrets.
3. Apply common and cloud migrations as the administrator, who owns new tables.
4. Reconcile runtime grants and default privileges.
5. Connect as each runtime login and verify table access and non-admin attributes.

The service connection role selects the same username per VM in cloud mode.
Application mode retains `oil_tracker`. Fetcher receives DML on
`published_queue_events`; History receives DML on `price_observations`. UI
receives no runtime login or grants here — its session store is Redis, not
PostgreSQL. Runtime roles do not receive ownership,
CREATE DATABASE, CREATE ROLE, or superuser attributes. Schema CREATE is revoked
from PUBLIC. Future tables require explicit grants in grants.sql; default
privileges revoke PUBLIC table/sequence access for the migration administrator.
Existing removed VM roles are not dropped automatically, and externally granted
role memberships are not managed here. Rotating a runtime password requires
coordinating migration and service redeployment because existing clients retain
old credentials until restarted.

SQL uses psql environment variables and PostgreSQL identifier/literal quoting,
not password interpolation into SQL files. Repeat runs reuse roles and replay
the existing idempotent migrations. The role fails immediately on SQL errors;
migrations commit individually, so a failed run can leave earlier changes in
place for a retry. Verification runs during deployment, not as a local test suite.

The application has since moved to RabbitMQ (Fetcher/History) and Redis (UI
sessions) in both database modes; this role only bootstraps the managed
PostgreSQL instance itself and is unrelated to that messaging/session
conversion. No cloud deployment or SQL execution has been performed locally.
