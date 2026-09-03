# Multi-cloud task checkpoint

Date: 2026-09-03

## Goal being implemented

The user explicitly requested implementation of the two remaining assignment
items:

1. Move VM images into the provider lookup dictionaries in the shared JSON.
2. Update the Ansible dynamic inventory to discover both GCP and AWS VMs using
   the same `default_cloud` / optional `vms.*.cloud` logic.

Learning and Mentoring Mode remains the default for later requests, but this
specific implementation was explicitly authorized.

## Work completed in this session

### Image lookup contract

Changed `project-config.example.json`:

- added top-level `images`;
- added logical image key `ubuntu-2604`;
- `images.ubuntu-2604.gcp.reference` stores the GCP image reference;
- `images.ubuntu-2604.aws.name_filter` and `.owners` store AWS AMI lookup data;
- every VM now contains `image: "ubuntu-2604"` instead of a GCP image path.

Changed `infrastructure/terraform/project-config.schema.json`:

- added `images` to root `required`;
- added validation for logical image mappings;
- GCP image mapping requires `reference`;
- AWS image mapping requires `name_filter` and at least one 12-digit owner ID.

Changed the provider wrappers:

- `modules/gcp/locals.tf` resolves
  `config.images[vm.image][cloud_key]` into `image_config`;
- `modules/gcp/main.tf` passes `image_config.reference` to the GCP VM module;
- `modules/aws/locals.tf` resolves the same lookup into `image_config`;
- `modules/aws/vm/variables.tf` accepts the resolved AWS image object;
- `modules/aws/vm/main.tf` creates one `data.aws_ami.ubuntu` lookup per VM and
  uses its `name_filter` and `owners` from JSON;
- `aws_instance.workload` uses `data.aws_ami.ubuntu[each.key].id`.

The data flow is now:

```text
root jsondecode
  -> complete config passed to modules/gcp and modules/aws
  -> provider wrapper selects its VMs
  -> config.images[logical image][cloud key]
  -> provider-specific VM resource/data source
```

### Managed cloud label/tag

Adjusted GCP labels and AWS tags so the resolved cloud is written as the
managed `cloud` value after user labels are merged. This is required because
the dynamic inventory filters live resources by `cloud=gcp` / `cloud=aws`.

### Multi-cloud dynamic inventory

Reworked
`infrastructure/ansible/oilscope/platform/plugins/inventory/oilscope_gcp.py`.
The historical plugin filename and FQCN were retained for compatibility, but
the plugin is now multi-cloud.

Current behavior:

- reads the shared JSON once;
- calculates effective cloud as `vm.cloud` or `default_cloud`;
- partitions configured VMs into GCP and AWS maps;
- skips a provider delegate when its selected map is empty;
- resolves GCP zones from `regions[vm.region].gcp.zone`;
- resolves AWS regions from `regions[vm.region].aws.region`;
- calls `google.cloud.gcp_compute` for GCP;
- calls `amazon.aws.aws_ec2` for AWS;
- filters GCP by `application`, `environment`, `cloud=gcp`, and running state;
- filters AWS by `application`, `environment`, `cloud=aws`, and running state;
- produces the same role groups for both providers;
- normalizes `internal_ip`, `public_ip`, `ansible_host`, `ansible_port`,
  `oilscope_role`, and `oilscope_cloud`.

Updated dependencies:

- `infrastructure/ansible/requirements.yml` now includes `amazon.aws >= 11.2`;
- `infrastructure/ansible/requirements.txt` now includes boto3 and botocore;
- inventory README was rewritten for GCP + AWS;
- the collection README now uses `inventory/oilscope.yml`.

## Verification already performed

- `terraform fmt -recursive infrastructure/terraform`: passed.
- `terraform fmt -check -recursive infrastructure/terraform`: passed.
- `git diff --check`: passed.
- Both changed JSON files were successfully decoded with Perl `JSON::PP`.
- Python source was parsed with Neovim Tree-sitter: zero syntax-error nodes.
- Python source was compiled with Python 3.14 `compile(...)`: passed.
- `ansible-doc` successfully loaded and rendered documentation for
  `oilscope.platform.oilscope_gcp` when the source collection was exposed via
  a temporary collection path.

`terraform validate` cannot run successfully inside the Codex sandbox because
the downloaded AWS and Google provider executables cannot start there. The
same repository previously validates successfully in the user's normal NixOS
terminal.

The last attempted direct Python import failed because Ansible tried to create
`~/.ansible/tmp` in a read-only sandbox. This is an environment restriction,
not a Python syntax failure. Set `ANSIBLE_LOCAL_TEMP` to a directory under
`/tmp` for the next sandbox test.

## Important remaining checks/fixes

1. Fix the pre-existing schema/example mismatch for UI ports:
   `project-config.example.json` has `[443]`, while the schema currently has
   `minItems: 2`. If HTTPS-only is valid, change schema `minItems` to `1`.
2. Run the JSON Schema validator against `project-config.example.json`.
3. Test `_build_settings` offline for three configurations:
   all GCP, all AWS, and mixed default/override.
4. Verify the exact constructed-variable expressions used by
   `amazon.aws.aws_ec2`, especially `ec2_tags`, `public_ip_address`, and
   `private_ip_address`, against the installed collection version.
5. Build/install the local `oilscope.platform` collection and run
   `ansible-inventory --graph` against live resources.
6. Update the user's private `/home/xintaro/dev.json` to add `images` and
   replace each provider image path with the logical image key. Do not commit
   that private environment file.
7. Run `terraform validate` and `terraform plan` in the user's normal shell.
8. Inspect the final diff for unrelated or pre-existing dirty-worktree changes
   before committing.

Potential follow-up outside these two requested items: the Ansible secret roles
still contain old `config.project_id` fallbacks and remain GCP-specific. Do not
silently expand the current task into multi-cloud secret management without
explicit scope confirmation.

## Dependencies/commands for the next session

The repository now declares the required dependencies. Install them with:

```sh
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
```

For schema validation, make `check-jsonschema` available (for example through
`uvx` or Nix), then run:

```sh
check-jsonschema \
  --schemafile infrastructure/terraform/project-config.schema.json \
  project-config.example.json
```

For the inventory source, rebuild and install the local collection:

```sh
cd infrastructure/ansible/oilscope/platform
ansible-galaxy collection build --force
ansible-galaxy collection install oilscope-platform-*.tar.gz --force
```

Then, from the repository root:

```sh
export AWS_PROFILE=terraform
export OILSCOPE_PROJECT_CONFIG=/home/xintaro/dev.json
ansible-inventory \
  -i infrastructure/ansible/inventory/oilscope.yml \
  --graph
```

Relevant official references:

- AWS EC2 inventory plugin:
  https://docs.ansible.com/projects/ansible/latest/collections/amazon/aws/aws_ec2_inventory.html
- GCP Compute inventory plugin:
  https://docs.ansible.com/projects/ansible/latest/collections/google/cloud/gcp_compute_inventory.html
- Terraform `for_each`:
  https://developer.hashicorp.com/terraform/language/meta-arguments/for_each
- Terraform lookup function:
  https://developer.hashicorp.com/terraform/language/functions/lookup
