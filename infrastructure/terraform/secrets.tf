module "gcp_secrets" {
  source = "./modules/gcp/secrets"

  config                 = local.config
  project_services       = module.gcp_project.services
  service_account_emails = module.gcp_vm.service_account_emails
}

module "aws_secrets" {
  source = "./modules/aws/secrets"

  config         = local.config
  iam_role_names = module.aws_vm.iam_role_names
}

moved {
  from = module.gcp_secrets[0]
  to   = module.gcp_secrets
}

moved {
  from = module.aws_secrets[0]
  to   = module.aws_secrets
}

moved {
  from = google_secret_manager_secret.this
  to   = module.gcp_secrets.google_secret_manager_secret.this
}

moved {
  from = google_secret_manager_secret_iam_member.workload_access
  to   = module.gcp_secrets.google_secret_manager_secret_iam_member.workload_access
}

moved {
  from = google_secret_manager_secret_iam_member.version_adder
  to   = module.gcp_secrets.google_secret_manager_secret_iam_member.version_adder
}
