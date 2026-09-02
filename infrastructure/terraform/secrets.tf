locals {
  all_secret_ids = distinct(flatten([
    for workload in values(local.workload_vms) : values(workload.secret_mappings)
  ]))

  gcp_workload_secret_access = {
    for name, workload in local.gcp_vms : name => distinct(values(workload.secret_mappings))
    if workload.role != "bastion"
  }

  aws_workload_secret_access = {
    for name, workload in local.aws_vms : name => distinct(values(workload.secret_mappings))
    if workload.role != "bastion"
  }
}

module "gcp_secrets" {
  count  = contains(local.enabled_clouds, "gcp") ? 1 : 0
  source = "./modules/gcp-secrets"

  labels                  = local.config.common_labels
  workload_secret_access  = local.gcp_workload_secret_access
  service_account_emails  = { for name, vm in module.gcp_vm : name => vm.service_account_email }
  secret_version_managers = local.config.clouds.gcp.secret_version_managers

  depends_on = [module.gcp_project]
}

module "aws_secrets" {
  count  = contains(local.enabled_clouds, "aws") ? 1 : 0
  source = "./modules/aws-secrets"

  tags                   = local.config.common_labels
  workload_secret_access = local.aws_workload_secret_access
  iam_role_names         = { for name, vm in module.aws_vm : name => vm.iam_role_name }
}

moved {
  from = google_secret_manager_secret.this
  to   = module.gcp_secrets[0].google_secret_manager_secret.this
}

moved {
  from = google_secret_manager_secret_iam_member.workload_access
  to   = module.gcp_secrets[0].google_secret_manager_secret_iam_member.workload_access
}

moved {
  from = google_secret_manager_secret_iam_member.version_adder
  to   = module.gcp_secrets[0].google_secret_manager_secret_iam_member.version_adder
}
