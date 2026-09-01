# GCP VM

The GCP half of the VM contract: one Compute Engine instance with its own
service account, a static internal address, and optionally a static external
one. It accepts the same variables as `modules/aws/vm` and returns the same
outputs.

`machine_type`, `image` and `boot_disk_type` arrive already resolved from the
portable tokens in the project configuration - the module never sees `micro` or
`balanced`.

`network_groups` carries Compute Engine network tags here and security group
IDs in the AWS module; `runtime_identity` is the service-account email here and
an IAM role name there. The root module uses both without knowing which cloud
produced them.

## Variables

`name`, `role`, `subnet_id`, `network_groups`, `machine_type`, `image`,
`internal_ip`, `boot_disk_size_gb`, `boot_disk_type`, `assign_public_ip`,
`labels`, `ssh_users`.

## Outputs

`name`, `internal_ip`, `public_ip`, `network_groups`, `runtime_identity`.
