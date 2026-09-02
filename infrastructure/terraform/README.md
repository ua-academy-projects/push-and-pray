# Multi-cloud Terraform

`project-config.example.json` is the provider-neutral input contract and
`project-config.schema.json` is its Draft 2020-12 schema. Logical region, size,
disk, and image values resolve through `cloud_mappings` after applying
`default_cloud` and optional per-VM `cloud` or `region` overrides. Entries in
`clouds` declare the providers the deployment is allowed to use.

VM addresses are provider-assigned from the subnet selected by role. Bastion
and UI use the management/public subnet on AWS; database, history, and fetcher
use the private workload subnet. On GCP, bastion uses the management subnet and
all application roles use the workload subnet. Only bastion and UI receive
public addresses. Terraform outputs expose the assigned addresses for dynamic
inventory and operations.

AWS private-subnet internet egress is intentionally disabled by default.
Setting `network.aws_enable_nat_gateway=true` creates a paid NAT Gateway. Keep
it disabled when private endpoints, mirrors, or another egress design provide
the APIs and artifacts workloads require.

## Credential-free tests

The native Terraform tests mock both providers and never create resources or
contact cloud APIs. They cover GCP-only, AWS-only, hybrid provider resolution,
invalid same-provider multi-region placement, and overlapping subnets:

```sh
python infrastructure/terraform/tests/generate_test_configs.py
python infrastructure/terraform/tests/validate_test_configs.py
terraform -chdir=infrastructure/terraform test
```

Generated configurations live under `.terraform/test-configs` and are ignored
by Git.
