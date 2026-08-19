# Secrets

Runtime secrets live in Google Secret Manager. Terraform creates the secret
containers and the access policy around them; it never creates a secret
*version*. No secret value is passed to Terraform, written into Terraform
state, or committed to this repository.

## What Terraform owns

| Terraform owns | Terraform does not own |
| --- | --- |
| The `secretmanager.googleapis.com` API being enabled | Any secret value |
| The secret containers, their replication and labels | Any secret version |
| Read access (`roles/secretmanager.secretAccessor`) per secret, per VM | The upstream credential itself (the key at the provider, the PostgreSQL role) |
| Write access (`roles/secretmanager.secretVersionAdder`) for named principals | Delivering values into the running containers |

`google_secret_manager_secret_version` is deliberately absent from the
configuration. A version resource would mean the payload arrives as Terraform
input and ends up in plaintext in `terraform.tfstate`, which is exactly what
this design avoids.

## Where the access map comes from

Nothing about access is hard-coded in Terraform. Both the list of secrets and
who may read them are derived from the project JSON:

```json
{
  "vms": [
    {
      "name": "ui",
      "role": "ui",
      "secret_ids": ["oilscope-dev-db-password-ui"]
    }
  ]
}
```

- **Which secrets exist**: the union of every `secret_ids` entry across all
  VMs. A secret nothing reads is never created; a secret a VM asks for is
  always created.
- **Who may read a secret**: exactly the service accounts of the VMs that list
  it. The grant is made on that one secret, never at project scope.

Because the containers and the grants come from the same field, the two cannot
drift apart. Listing a secret ID that does not exist elsewhere in the file is
not a silent misconfiguration — Terraform creates it.

To see the resulting map without opening the console:

```bash
terraform output secret_access_map
```

and to confirm the live policy matches what Terraform believes:

```bash
gcloud secrets get-iam-policy oilscope-dev-db-password-ui --project PROJECT_ID
```

## Granting access

Add the secret ID to that VM's `secret_ids` in the project JSON and apply:

```bash
terraform plan -var="project_config_path=/absolute/path/to/dev.json" -out=tfplan
terraform apply tfplan
```

## Revoking access

Remove the secret ID from that VM's `secret_ids` and apply. Terraform destroys
the corresponding `google_secret_manager_secret_iam_member`, and the VM's
service account loses `secretAccessor` on that secret only — every other grant
is untouched, because each one is a separate resource.

Two things to know:

- **Revocation is not retroactive.** If the VM has already read the value, it
  still has it, and a running process keeps whatever it loaded at start. When
  you revoke because of a suspected compromise, rotate the credential too.
- **Effect is not instant.** IAM changes propagate within about two minutes,
  occasionally longer. Do not conclude the change failed from a single
  immediate retry.

To take a secret out of service entirely, remove it from every VM's
`secret_ids`. The container is then no longer in the union and Terraform
destroys it, along with every version inside it — there is no undo.

## Storing a value

Only principals listed in the `secret_version_managers` Terraform input can do
this. `roles/secretmanager.secretVersionAdder` allows adding a new version and
nothing else — it does not allow reading existing payloads.

Generate a database password and store it without the value reaching your shell
history or the filesystem:

```bash
printf '%s' "$(openssl rand -hex 32)" \
  | gcloud secrets versions add oilscope-dev-db-password-ui \
      --project PROJECT_ID --data-file=-
```

`-hex` rather than `-base64`: the password ends up inside a `postgres://` URL,
and base64 output contains `+` and `/`, which change what that URL means.

Store a value you were given, such as an API key:

```bash
read -rs -p "OilPriceAPI key: " VALUE && echo
printf '%s' "${VALUE}" \
  | gcloud secrets versions add oilscope-dev-oilpriceapi-key \
      --project PROJECT_ID --data-file=-
unset VALUE
```

`read -rs` keeps the value off the terminal and out of shell history;
`printf '%s'` avoids a trailing newline that would silently become part of the
password. Never `echo "the-value" | ...` with the value typed inline, and do
not use `--data-file=some-file` unless you delete the file afterwards.

## Reading a value at runtime

The workload VMs run with the `cloud-platform` OAuth scope and their own
service account, so nothing further needs configuring:

```bash
gcloud secrets versions access latest \
  --secret=oilscope-dev-db-password-ui --project PROJECT_ID
```

Values are fetched when a service starts, not baked into an image or a file.
Whatever performs the injection must pass them through the **process
environment only**: no `.env` file on disk, no secret on a command line, no
secret in a Compose file committed here.

A VM asking for a secret that is not in its `secret_ids` gets
`PERMISSION_DENIED`. That is the intended way to verify the map is real rather
than decorative — try to read another role's secret from the `ui` VM and
confirm it fails.

The mechanism that loads these into the running containers is not part of this
configuration. Terraform provides the storage and the boundary; delivery is
handled separately.

## Rotation

1. Add a new version with the commands above. `latest` immediately points at it.
2. Apply the new value upstream — regenerate the key at the provider, or
   `ALTER ROLE ... WITH PASSWORD ...` in PostgreSQL.
3. Restart the consuming service so it picks the new value up. A running
   process keeps the value it read at start; adding a version changes nothing
   on its own.
4. Only then retire the old version:

```bash
gcloud secrets versions disable 3 --secret=oilscope-dev-db-password-ui --project PROJECT_ID
# after confirming nothing broke
gcloud secrets versions destroy 3 --secret=oilscope-dev-db-password-ui --project PROJECT_ID
```

Disable first, destroy later: a disabled version can be re-enabled if something
was still using it, a destroyed one cannot.

## If a secret leaks

A value that has appeared in a repository, a build log, a screenshot or a chat
is compromised, whether or not anyone can prove it was read. Deleting the
commit does not undo it.

1. **Invalidate the credential at its source first.** Regenerate the key at the
   provider; change the PostgreSQL role's password. Until this is done, nothing
   you do in Secret Manager matters — the leaked string still works.
2. Add the new value as a new secret version.
3. Restart the affected services.
4. Destroy the leaked version, and check `gcloud secrets get-iam-policy` for any
   grant that should not be there.
5. Purge the value from wherever it appeared, and confirm the `Secret scan` job
   in `.github/workflows/security.yml` is clean afterwards.

Steps 2–5 without step 1 are theatre.

## Destroying the environment

`terraform destroy` deletes the secret containers, and deleting a container
deletes every version inside it. There is no undo and no export. Before
destroying a non-throwaway environment, confirm that every value can be
regenerated or is stored somewhere else.
