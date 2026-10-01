module "gcp" {
  source = "./modules/gcp"

  config                       = local.config
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  secret_version_managers      = var.secret_version_managers
}

module "aws" {
  source = "./modules/aws"

  config                       = local.config
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

module "azure" {
  source = "./modules/azure"

  config                       = local.config
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

check "multicloud_k3s_topology" {
  assert {
    condition = !local.kubernetes_enabled || (
      length([for vm in values(local.config.vms) : vm if vm.role == "k3s_server"]) == 3 &&
      length(distinct([for vm in values(local.config.vms) : lookup(vm, "cloud", local.config.default_cloud) if vm.role == "k3s_server"])) == 3 &&
      alltrue([for cloud in ["gcp", "aws", "azure"] : length([for vm in values(local.config.vms) : vm if vm.role == "bastion" && lookup(vm, "cloud", local.config.default_cloud) == cloud]) == 1])
    )
    error_message = "A multi-cloud Kubernetes deployment needs three k3s_server VMs in distinct clouds and one bastion in each cloud."
  }
}

resource "cloudflare_dns_record" "example_dns_record" {
  zone_id = local.config.zone_id
  name    = local.config.vms[local.public_endpoint_vm_name].public_endpoint.hostname
  ttl     = 3600
  type    = "A"
  comment = "Domain verification record"
  content = local.ui_public_ip
  proxied = false
}
