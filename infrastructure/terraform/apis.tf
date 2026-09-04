module "gcp_project" {
  source = "./modules/gcp/project"

  config = local.config
}
