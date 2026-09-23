module "gcp_vm" {
  source = "./modules/gcp"

  config = local.config
}

module "aws_vm" {
  source = "./modules/aws"

  config = local.config
}

module "cloudflare" {
  source = "./modules/cloudflare"

  config = local.config
}

module "azure_vm" {
  source = "./modules/azure"

  config = local.config
}