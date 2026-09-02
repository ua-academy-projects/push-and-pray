locals {
  name = "${var.resource_prefix}-bootstrap"
}

resource "aws_key_pair" "bootstrap" {
  key_name   = local.name
  public_key = trimspace(one(values(var.ssh_users)))
  tags       = merge(var.tags, { Name = local.name })
}
