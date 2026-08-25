# Secrets

Deployment credentials live in Google Secret Manager. Terraform creates the
containers and decides who may read them; it never sees, stores or transports a
value.

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

`infrastructure/terraform/secrets.tf` flattens those maps into the set of
containers to create, and into the list of (workload, secret) pairs to grant.
Giving a workload a new secret is a one-line change to that JSON — the
container, the grant and the environment-variable name all follow from it.

The same derivation is what makes the access rule enforceable: a workload can
only be granted a secret that is written next to its own name.

## What Terraform does, and what it deliberately does not

| Terraform | |
| --- | --- |
| creates | `google_secret_manager_secret` — the container, automatic replication, project labels |
| creates | `google_secret_manager_secret_iam_member` — one `roles/secretmanager.secretAccessor` binding per (workload, secret) pair |
| creates | `google_secret_manager_secret_iam_member` — one `roles/secretmanager.secretVersionAdder` binding per configured version manager |
| never creates | `google_secret_manager_secret_version` — the payload |

The last row is the whole point. A secret value passed into Terraform ends up in
three places you cannot fully control: the configuration file, the plan file, and
the state file. State lives in a bucket, plans get attached to pull requests, and
neither is a place for a credential. So versions are added out of band and
Terraform is told nothing about them.

`google_secret_manager_secret_iam_member` is used rather than
`..._iam_binding`. The `_binding` form is authoritative for the whole role on
that secret: it silently removes any grant made outside Terraform. `_member` adds
one principal and leaves the rest of the policy alone.

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

Each workload VM runs as its own service account and is granted only the secrets
listed against it. There is no project-wide `secretAccessor` binding, so a
compromised VM reaches its own credentials and nothing else. This is also why the
database passwords are separate secrets rather than one shared value: a single
password would hand every workload the same blast radius.

`terraform output secret_ids` lists the containers, and
`terraform output secret_resource_names` gives their fully qualified names.
None of the three outputs exposes a value.

## Storing a value

Values are written with `gcloud`, from a pipe, never from a command-line
argument — arguments are visible in `ps` output and land in shell history:

```bash
printf '%s' "${DB_PASSWORD_HISTORY}" \
  | gcloud secrets versions add oilscope-dev-db-password-history \
      --project="${GOOGLE_PROJECT}" --data-file=-
```

Note `printf` rather than `echo`: `echo` appends a newline, which becomes part of
the stored value and then fails an exact comparison somewhere far away from here.

Which environment variable holds which value is not a convention to remember —
it is the key side of `secret_mappings`. Read it from the configuration rather
than deriving it from the secret's name.

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

## Rotation

Adding a version does not remove the old one. Secret Manager keeps every version
until it is destroyed, and consumers that ask for `latest` pick up the new value
on their next read.

```bash
printf '%s' "${NEW_VALUE}" | gcloud secrets versions add SECRET_ID --data-file=-
gcloud secrets versions list SECRET_ID
gcloud secrets versions destroy VERSION --secret=SECRET_ID   # once nothing reads it
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
