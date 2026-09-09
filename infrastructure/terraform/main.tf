module "gcp_vm" {
  source = "./modules/gcp"

  config = local.config
}

module "aws_vm" {
  source = "./modules/aws"

  config = local.config
}
