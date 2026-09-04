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
