locals {
  resource_prefix          = "${var.config.name_prefix}-${var.config.environment}"
  bootstrap_ssh_public_key = var.config.ssh_users[sort(keys(var.config.ssh_users))[0]]
  labels = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )
}

resource "aws_key_pair" "bootstrap" {
  for_each = var.networks

  region     = each.value.region
  key_name   = "${local.resource_prefix}-${each.key}-bootstrap"
  public_key = local.bootstrap_ssh_public_key
  tags       = local.labels
}
