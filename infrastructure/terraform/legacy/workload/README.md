# Legacy workload configuration

This directory preserves the incomplete workload implementation left by the
configuration merge. Terraform does not load `.tf` files recursively, and the
active root module does not reference this directory, so these files are not
part of the current configuration.

The preserved implementation includes four workload VMs (`infra`, `history`,
`fetcher`, and `ui`), their service accounts, Secret Manager resources and IAM
bindings, workload locals and variables, and cloud-init assets.

It still references resources from the previous network implementation and is
not independently valid. Do not apply it. Workload compute will be adapted to
the active `module.network` interface in a later refactoring stage.
