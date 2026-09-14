# Configuration ownership

Project JSON is a non-secret contract shared by Terraform and Ansible.
Terraform reads it once at root and passes structured objects to children.
Private keys, credentials and secret payloads do not belong in this file.

| Fields | Consumer and reason |
| --- | --- |
| `name_prefix`, `environment` | Terraform names/identity labels and inventory filters |
| `default_cloud`, optional `vms.*.cloud` | Provider selection; overrides only when different |
| `default_region`, optional `vms.*.region` | Logical placement with inheritance |
| `clouds.gcp.project_id` | GCP provider, APIs, inventory and secret resolution |
| `clouds.aws` | AWS provider declaration; no unused account ID |
| `cloud_mappings.regions.*.{gcp,aws}.{region,zone}` | Provider/network placement, VM validation, inventory |
| `cloud_mappings.sizes.*.{gcp,aws}` | VM machine types; `micro`/`small` describe actual mapped shapes |
| `cloud_mappings.disk_types.*.{gcp,aws}` | VM boot disk types with default performance |
| `cloud_mappings.images.*.gcp.{project,family}` | GCP boot image family |
| `cloud_mappings.images.*.aws.{owners,name_pattern}` | AWS AMI ownership and discovery |
| `common_labels`, optional `vms.*.labels` | Resource metadata; identity keys are reserved |
| `ssh_users` | Linux usernames/public SSH keys; private keys remain on controller |
| `registry.{repository,username,image_sha}` | Ansible registry login and Compose image references |
| `network.vpc_cidr` | AWS VPC range and global subnet containment; GCP VPCs have no CIDR property |
| `network.{management_subnet_cidr,workload_subnet_cidr}` | Provider subnets and non-overlap validation |
| `network.aws_enable_nat_gateway` | Explicit AWS egress choice; false in example |
| `network.ui_public_ports` | Firewall policy; 80/443 for HTTP redirect, ACME and HTTPS |
| `service_ports.{history_api,postgresql,rabbitmq,redis}` | Firewall policy and Ansible bindings/connections |
| `vms.*.{role,size,image,boot_disk.size_gb,boot_disk.type,assign_public_ip}` | Identity, capacity, image, storage and public addressing |
| `vms.bastion.{ssh_port,allowed_cidrs}` | Bootstrap, SSH enforcement and firewall restrictions |
| `application.secret_mappings.<role>.<ENV>` | Ansible environment mapping; Terraform consumes referenced IDs for containers/IAM |
| `application.public_endpoint.{hostname,acme_email}` | Ansible Traefik routing and ACME |

Mappings need only include providers that use them. Schema checks structure;
Terraform checks effective mapping availability and deployment invariants.

`registry.image_sha` means deployment source version, not one image digest.
`publish-images.yaml` calls the same reusable workflow for database, history,
fetcher and UI; each gets the full `github.sha` tag. All four deployment images
therefore share one version. Terraform VM creation does not consume registry
settings.

Cleanup renamed logical `small` to `micro` and `medium` to `small` while
preserving machine mappings. VM `secret_mappings` moved into the application
role map; UI `public_endpoint` moved into application settings. The redundant
schema default for the required NAT flag and unused VM registry/bootstrap
rendering inputs were removed. No IOPS field or AWS account ID was added.
