# Secrets

Deployment credentials live in Google Secret Manager (GCP) or AWS Secrets
Manager (AWS), depending on `default_cloud` in the project configuration.
For workload secrets, Terraform creates containers and decides who may read
them without handling values. Managed database administrator credentials are
the exception described below. Everything else applies to both clouds unless
a section says otherwise.

## Where the catalog comes from

There is no hand-written list of secrets. Every container is derived from
`secret_mappings` in the project configuration JSON:

```json
"vms": {
  "history": {
    "role": "history",
    "secret_mappings": {
      "DB_PASSWORD_HISTORY": "oilscope-dev-db-password-history"
    }
  }
}
```

The key is the environment variable the application expects; the value is the
Secret Manager container ID. Both halves are non-secret, which is why the whole
mapping can live in a file the repository reads.

`infrastructure/terraform/modules/gcp/secrets` and
`infrastructure/terraform/modules/aws/secrets` each flatten those maps into
the set of containers to create, and into the list of (workload, secret)
pairs to grant, for their own cloud.
Giving a workload a new secret is a one-line change to that JSON — the
container, the grant and the environment-variable name all follow from it.

The same derivation is what makes the access rule enforceable: a workload can
only be granted a secret that is written next to its own name.

## What Terraform does, and what it deliberately does not

GCP:

| Terraform | |
| --- | --- |
| creates | `google_secret_manager_secret` — the container, automatic replication, project labels |
| creates | `google_secret_manager_secret_iam_member` — one `roles/secretmanager.secretAccessor` binding per (workload, secret) pair |
| creates | `google_secret_manager_secret_iam_member` — one `roles/secretmanager.secretVersionAdder` binding per configured version manager |
| never creates | `google_secret_manager_secret_version` — the payload |

AWS:

| Terraform | |
| --- | --- |
| creates | `aws_secretsmanager_secret` — the container, tags |
| creates | `aws_iam_role_policy` — one `secretsmanager:GetSecretValue` grant per workload, scoped to that workload's own secrets |
| never creates | a secret *version* — the payload |

The last row of each table is the whole point. A secret value passed into
Terraform ends up in three places you cannot fully control: the configuration
file, the plan file, and the state file. State lives in a bucket, plans get
attached to pull requests, and neither is a place for a credential. So
versions are added out of band and Terraform is told nothing about them.

`google_secret_manager_secret_iam_member` is used rather than
`..._iam_binding`. The `_binding` form is authoritative for the whole role on
that secret: it silently removes any grant made outside Terraform. `_member` adds
one principal and leaves the rest of the policy alone.

One asymmetry: on GCP, `secret_version_managers` lets Terraform also grant
specific principals permission to *add* versions (`secretVersionAdder`,
deliberately not `secretAccessor` — see below). AWS has no equivalent
Terraform-managed grant yet; whoever uploads a version on AWS needs
`secretsmanager:PutSecretValue` (and `DescribeSecret`, since the uploader
checks a container exists before writing to it) from their own broader AWS
identity, not from anything this repository's Terraform grants.

## Who can read what

The access map is an output, so it can be checked without reading any Terraform:

```bash
terraform output workload_secret_access
```

```
{
  "fetcher" = ["oilscope-dev-db-password-fetcher", "oilscope-dev-oilpriceapi-key"]
  "history" = ["oilscope-dev-db-password-history"]
  ...
}
```

Each workload VM runs as its own identity — a service account on GCP, an
instance role on AWS — and is granted only the secrets listed against it.
There is no project-wide (GCP) or account-wide (AWS) read grant, so a
compromised VM reaches its own credentials and nothing else. This is also why the
database passwords are separate secrets rather than one shared value: a single
password would hand every workload the same blast radius.

`terraform output secret_ids` lists the containers, and
`terraform output secret_resource_names` gives their fully qualified names.
None of the three outputs exposes a value.

## Storing a value

On GCP, values are written with `gcloud`, from a pipe, never from a
command-line argument — arguments are visible in `ps` output and land in
shell history:

```bash
printf '%s' "${DB_PASSWORD_HISTORY}" \
  | gcloud secrets versions add oilscope-dev-db-password-history \
      --project="${GOOGLE_PROJECT}" --data-file=-
```

Note `printf` rather than `echo`: `echo` appends a newline, which becomes part of
the stored value and then fails an exact comparison somewhere far away from here.

On AWS, the AWS CLI has no stdin equivalent of `--data-file=-` for
`put-secret-value` — its `--secret-string` takes either a literal argument or
a `file://` path. Never pass the value as a literal argument; write it to a
private (`0600`), short-lived file instead and reference that:

```bash
umask 077
printf '%s' "${DB_PASSWORD_HISTORY}" > /tmp/db-password-history.tmp
aws secretsmanager put-secret-value \
  --secret-id oilscope-dev-db-password-history \
  --region "${AWS_REGION}" \
  --secret-string file:///tmp/db-password-history.tmp
rm -f /tmp/db-password-history.tmp
```

The `oilscope.platform.secret_versions` role (below) does exactly this and
guarantees the temporary file is removed even if the upload fails - prefer it
over the manual form above for anything beyond a one-off.

Which environment variable the *application* reads is not a convention to
remember: it is the key side of `secret_mappings`. It is scoped to one VM
though, so it is not the variable you export when uploading — see
[Uploading every value at once](#uploading-every-value-at-once).

Generate database passwords with `openssl rand -hex 32`. `-hex` rather than
`-base64`, because base64 contains `+` and `/`, which have to be percent-encoded
inside a `postgres://` URL and break it if they are not.

Adding versions requires `roles/secretmanager.secretVersionAdder`. That grant is
made by Terraform from the `secret_version_managers` variable:

```hcl
secret_version_managers = [
  "user:name@example.com",
]
```

`secretVersionAdder` is deliberately not `secretAccessor`. It allows adding a new
version and nothing else — a person listed here can rotate a credential without
being able to read the current one. Reading is what the workload service accounts
do, and they hold only `secretAccessor`, only on their own secrets.

Leave the list empty and nobody but a project owner can upload a value, which is
a reasonable default: it fails closed.

AWS has no `secret_version_managers` equivalent: Terraform grants no one
write access to a secret's versions. Whoever uploads needs
`secretsmanager:PutSecretValue` from their own broader AWS identity.

## Uploading every value at once

Doing that by hand for every secret is where a value eventually ends up in the
wrong place. The `oilscope.platform.secret_versions` role does the whole
catalog in one pass, taking each value from the environment of the operator who
runs it. It targets `localhost`: this is an operator task against the cloud
API, not host configuration. It uploads to whichever single cloud the
configuration's VMs resolve to, and refuses to run against a configuration
that resolves to more than one.

```bash
 export DB_PASSWORD_ADMIN="$(openssl rand -hex 32)"
 export DB_PASSWORD_FETCHER="$(openssl rand -hex 32)"
 export DB_PASSWORD_HISTORY="$(openssl rand -hex 32)"
 export DB_PASSWORD_UI="$(openssl rand -hex 32)"
 export OILPRICEAPI_KEY="..."

ansible-playbook oilscope.platform.upload_secret_versions \
  -e secret_versions_config_file=~/configs/oilscope/dev.json --check

ansible-playbook oilscope.platform.upload_secret_versions \
  -e secret_versions_config_file=~/configs/oilscope/dev.json
```

The leading space keeps the export out of the shell history, in a shell
configured to honour it. `--check` runs every check and uploads nothing; the
role prints which variable feeds which container before it writes anything.

### Why the variable is not the one the application sees

The unit of upload is the container, so the variable name is derived from the
container ID with the project prefix dropped — not from the key side of
`secret_mappings`:

```
oilscope-dev-db-password-fetcher   ->  DB_PASSWORD_FETCHER
oilscope-dev-oilpriceapi-key       ->  OILPRICEAPI_KEY
```

That key is scoped to one VM: `DB_PASSWORD` means the fetcher's password on
`fetcher` and the history service's password on `history`, and one shell cannot
hold both under one name. Where dropping the prefix would make two containers
collide, every container keeps the fully qualified name
(`OILSCOPE_DEV_DB_PASSWORD_FETCHER`) instead.

### What it guarantees

| | |
| --- | --- |
| reads values from | the environment of the process, and nowhere else |
| passes the payload to gcloud (GCP) | on stdin, through `--data-file=-` |
| passes the payload to the AWS CLI (AWS) | via `--secret-string file://...`, a private (`0600`) temporary file removed unconditionally once the upload finishes or fails |
| writes to disk | nothing left behind once the role finishes |
| prints | container IDs and variable names, never a value |

Every value and every container is checked before the first version is added. A
missing one fails the play with the full list, before anything is written.
Half-rotated is the state that costs an evening — one service on the new
password, three on the old. On both clouds, the container itself must already
exist — this role only ever writes a version into what Terraform already
created; it never creates a container.

Every task that touches a value carries `no_log`, so the payload stays out of
the Ansible output and any callback log at every verbosity, and no trailing
newline is ever added (`stdin_add_newline: false` on GCP; a plain, unmodified
file write on AWS) because it would become part of the stored value. The
sensitive tasks are also skipped explicitly in check mode rather than being
left to the module: a check-mode skip result carries the module arguments,
and `-vvv` prints those
uncensored.

Rotating a single credential:

```bash
 export DB_PASSWORD_UI="$(openssl rand -hex 32)"

ansible-playbook oilscope.platform.upload_secret_versions \
  -e secret_versions_config_file=~/configs/oilscope/dev.json \
  -e '{"secret_versions_only": ["DB_PASSWORD_UI"]}'
```

Adding a version requires `roles/secretmanager.secretVersionAdder` (GCP) or
`secretsmanager:PutSecretValue` (AWS), so whoever runs this does not need to
be able to read what is already stored.

## Rotation

Adding a version does not remove the old one. Both Secret Manager and Secrets
Manager keep every version until it is destroyed, and consumers that ask for
the latest one pick up the new value on their next read.

```bash
# GCP
printf '%s' "${NEW_VALUE}" | gcloud secrets versions add SECRET_ID --data-file=-
gcloud secrets versions list SECRET_ID
gcloud secrets versions destroy VERSION --secret=SECRET_ID   # once nothing reads it

# AWS
umask 077; printf '%s' "${NEW_VALUE}" > /tmp/v.tmp
aws secretsmanager put-secret-value --secret-id SECRET_ID --region "${AWS_REGION}" --secret-string file:///tmp/v.tmp
rm -f /tmp/v.tmp
aws secretsmanager list-secret-version-ids --secret-id SECRET_ID --region "${AWS_REGION}"
# AWS has no destroy-one-version equivalent; the previous version stays as
# AWSPREVIOUS until the next PutSecretValue rotates the labels again, or the
# whole secret is deleted.
```

Destroy the previous version only after every consumer has restarted. Until then
it is the rollback.

## If a value leaks

Rotate first, clean up second. A credential that has been pushed to a public
repository, printed into a CI log or pasted into a chat is compromised from that
moment; deleting the commit or the log does not undo it.

1. Generate a new value and add it as a new version.
2. Restart the consumers so they pick it up.
3. Destroy the leaked version.
4. Only then remove the exposed copy from wherever it appeared.

`pre-commit` hooks and the `Secret scan` job in CI exist to make step 4 rare —
see the README and [security-scanning.md](security-scanning.md).

## One caveat on destroy

`terraform destroy` removes the containers and every version inside them. There
is no undo, and the values are not in state to be recovered from. Before
destroying a project that anyone else relies on, confirm the values exist
somewhere else first.

## Managed database administrator credentials

The database modules manage administrator credentials separately from workload
`secret_mappings`. Do not add these administrator secrets to application VM
mappings. Ansible will use an authorized migration identity to bootstrap
restricted runtime database roles in a later step.

AWS RDS generates its administrator password in Secrets Manager and Terraform
exports `admin_secret_arn` without reading the password. GCP Terraform generates
a 32-character password, creates `oil_tracker_admin`, and writes a JSON secret
with `username` and `password` under `<prefix>-<environment>-database-admin`.
`gcp_database_connection.admin_secret_id` exports the secret resource name only.

The GCP generated password, SQL user password, and secret payload are stored in
sensitive Terraform state. Sensitive marking hides normal CLI output; it does
not encrypt state or remove the values. Restrict backend access and protect
state backups. No secret values belong in project JSON, outputs, logs, or Git.
Keep password changes under Terraform management so the SQL account and secret
version stay synchronized; there is no automatic GCP password rotation here.
This differs from the RDS-managed password workflow.
