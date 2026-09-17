# State migration for flat Terraform modules

The code has been reorganized; the real resources and Terraform state have not
been changed. No automatic moved blocks are included, as requested.
Do not apply a destroy/create plan merely to finish this refactor.

1. Identify the correct backend and workspace and back up the current state.
   Store the backup outside Git; it may contain sensitive values.
2. List addresses from that state. Depending on the previously applied code,
   they can have old root paths or the intermediate `module.gcp/module.aws` paths.
3. Prepare reviewed `terraform state mv` operations (or temporary moved blocks)
   for addresses that actually exist. The table below is a mapping guide,
   not a script to execute blindly.
4. Move addresses under normal state locking. Do not create a new empty state
   for infrastructure that already exists.
5. Run a fresh plan with the same region, images, names, IPs and machine sizes.
   A state-address move cannot prevent replacement caused by changed real values.

| Previous intermediate address | New address |
| --- | --- |
| module.gcp.google_project_service.required | module.gcp_apis.google_project_service.required |
| module.gcp.module.network[0].google_compute_network.main | module.gcp_network.google_compute_network.main[0] |
| module.gcp.module.network[0].google_compute_subnetwork.management | module.gcp_network.google_compute_subnetwork.this["management"] |
| module.gcp.module.network[0].google_compute_subnetwork.workload | module.gcp_network.google_compute_subnetwork.this["workload"] |
| module.gcp.module.network[0].google_compute_router.main | module.gcp_network.google_compute_router.main[0] |
| module.gcp.module.network[0].google_compute_router_nat.main | module.gcp_network.google_compute_router_nat.main[0] |
| module.gcp.module.network[0].google_compute_firewall.<rule> | module.gcp_security.google_compute_firewall.<rule>[0] |
| module.gcp.module.vm["<vm>"].google_compute_instance.workload | module.gcp_vm.google_compute_instance.workload["<vm>"] |
| module.gcp.module.vm["<vm>"].google_compute_address.public[0] | module.gcp_vm.google_compute_address.public["<vm>"] |
| module.gcp.module.vm["<vm>"].google_service_account.workload | module.iam.google_service_account.vm["<vm>"] |
| module.gcp.google_secret_manager_secret.this | module.gcp_secrets.google_secret_manager_secret.this |
| module.gcp.google_secret_manager_secret_iam_member.workload_access | module.gcp_secrets.google_secret_manager_secret_iam_member.workload_access |
| module.gcp.google_secret_manager_secret_iam_member.version_adder | module.gcp_secrets.google_secret_manager_secret_iam_member.version_adder |
| module.aws.aws_vpc.this | module.aws_network.aws_vpc.this |
| module.aws.aws_subnet.this | module.aws_network.aws_subnet.this |
| module.aws.aws_internet_gateway.this | module.aws_network.aws_internet_gateway.this |
| module.aws.aws_route_table.public | module.aws_network.aws_route_table.public |
| module.aws.aws_route_table_association.this | module.aws_network.aws_route_table_association.this |
| module.aws.aws_security_group.vm | module.aws_security.aws_security_group.vm |
| module.aws.aws_vpc_security_group_egress_rule.all | module.aws_security.aws_vpc_security_group_egress_rule.all |
| module.aws.aws_vpc_security_group_ingress_rule.<rule> | module.aws_security.aws_vpc_security_group_ingress_rule.<rule> |
| module.aws.aws_instance.this | module.aws_vm.aws_instance.this |
| module.aws.aws_key_pair.operator | module.aws_vm.aws_key_pair.operator |
| module.aws_ec2_iam_role.aws_iam_role.this[0] | module.iam.aws_iam_role.ec2[0] |
| module.aws_ec2_iam_role.aws_iam_instance_profile.this[0] | module.iam.aws_iam_instance_profile.ec2[0] |

Replace placeholders with actual keys, preserving rule/VM identities.
Bootstrap firewall already had a [0] index: do not add a second index.
Earlier GCP root deployments used `module.network` and `module.vm["<vm>"]`;
use the addresses actually present, not the intermediate prefix.
If IAM was applied while nested in AWS, its old prefix may instead be
`module.aws.module.ec2_iam_role`.
The Babenko profile's existing name must be checked against the new desired
name before any role/profile change. Unapplied configuration needs no state move.
