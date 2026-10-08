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
  count   = local.eks_enabled || local.gke_enabled ? 0 : 1
  zone_id = local.config.zone_id
  name    = local.config.vms[local.public_endpoint_vm_name].public_endpoint.hostname
  ttl     = 3600
  type    = "A"
  comment = "Domain verification record"
  content = local.ui_public_ip
  proxied = false
}

resource "cloudflare_dns_record" "gke_ui" {
  count   = local.gke_enabled ? 1 : 0
  zone_id = local.config.zone_id
  name    = local.config.kubernetes.gke.public_endpoint.hostname
  ttl     = 1
  type    = "A"
  comment = "GKE UI ingress"
  content = module.gcp.gke.ingress_ip
  proxied = false
}

resource "cloudflare_dns_record" "eks_certificate_validation" {
  for_each = local.eks_enabled ? {
    (local.config.kubernetes.eks.public_endpoint.hostname) = one(module.aws.kubernetes.certificate_validation_options)
  } : {}

  zone_id = local.config.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  ttl     = 1
  content = each.value.resource_record_value
  proxied = false
  comment = "ACM validation for EKS UI"
}

resource "aws_acm_certificate_validation" "eks_ui" {
  count                   = local.eks_enabled ? 1 : 0
  certificate_arn         = module.aws.kubernetes.certificate_arn
  validation_record_fqdns = values(cloudflare_dns_record.eks_certificate_validation)[*].name
}
