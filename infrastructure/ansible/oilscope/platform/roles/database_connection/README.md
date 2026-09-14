# Database connection

Resolves non-secret PostgreSQL settings before `compose_project` renders the
Fetcher, History, or UI Compose file. Run with privilege escalation so the role
can install the public CA bundle under `/etc/oilscope/database-tls`.

Required input: `project_config_path`, the controller's project JSON file.
`default_db` is read explicitly, without an omitted-mode fallback.

In application mode, the role selects the database inventory host's internal
IP and the configured PostgreSQL service port. The database/user names remain
`oil_tracker`, the existing application contract. TLS stays disabled for this
existing self-hosted setup. No Terraform output file or CA download is needed.

In cloud mode, also supply `terraform_outputs_path`: an absolute controller path
to the full JSON from `terraform output -json` for this applied deployment.
Refresh that file after every infrastructure change or database-mode switch:

```sh
terraform -chdir=infrastructure/terraform output -json > /absolute/path/terraform-outputs.json
```

Add `-e terraform_outputs_path=/absolute/path/terraform-outputs.json` to the
usual deployment command, alongside its existing project, inventory, and
monitoring inputs. This role reads exported state metadata; it does not run
Terraform, apply infrastructure, or discover a different deployment. A stale
but valid file cannot be detected automatically, so refresh it from the correct
backend/workspace. This step does not make the full managed deployment ready.

The role selects `<default_cloud>_database_connection.value`, using the host,
port, database, TLS mode, and public CA URL exported by the AWS/GCP module.
A missing/null output or a mode other than `verify-full` stops the role rather
than falling back to the database VM or unverified TLS.

The public CA bundle is refreshed over verified HTTPS on each deployment.
`oilscope_database_environment` supplies the Compose host/port/database/user/TLS
variables; credentials continue through the existing secret-resolution roles.
Cloud runtime usernames are `oil_tracker_<vm-key>`; the managed migration role
creates them from existing workload password mappings. Application mode keeps
`oil_tracker`. Templates require these values instead of supplying database connection
fallbacks. Cloud templates include an explicit `sslrootcert` URL parameter and
mount the CA directory read-only at `/run/oilscope/database-tls`. Directory
mounting makes atomic CA file replacement visible. A CA checksum label changes
Compose configuration when the bundle changes, causing normal `compose up` to
recreate the service and reload its trust material. No mount is emitted in
application mode.

UI no longer runs this role: its session store moved to Redis, so it has no
PostgreSQL connection to resolve. Fetcher and History are the only workloads
that use it. Administrator secret retrieval, restricted runtime roles, and
managed migrations are handled by the separate `database_migrate` role.

No tests are added. Local syntax checks do not verify remote CA downloads,
DNS resolution, certificate identity, credentials, or database connectivity.
