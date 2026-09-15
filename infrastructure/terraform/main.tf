module "gcp" {
  source = "./modules/gcp"

  config                            = local.config
  enable_bastion_ssh_bootstrap      = var.enable_bastion_ssh_bootstrap
  secret_version_managers           = var.secret_version_managers
  managed_database_password         = var.managed_database_password
  managed_database_password_version = var.managed_database_password_version
}

module "aws" {
  source = "./modules/aws"

  config                       = local.config
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

resource "cloudflare_dns_record" "example_dns_record" {
  zone_id = local.config.zone_id
  name = local.config.vms[local.ui_vm_name].public_endpoint.hostname
  ttl = 3600
  type = "A"
  comment = "Domain verification record"
  content = local.ui_public_ip
  proxied = false
}
