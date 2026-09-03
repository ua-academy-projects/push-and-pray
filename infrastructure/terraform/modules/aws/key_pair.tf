resource "aws_key_pair" "operator" {
  key_name   = "${local.resource_prefix}-operator"
  count      = local.has_vms ? 1 : 0
  public_key = local.config.ssh_users["example-operator"]

  tags = merge(
    local.common_labels,
    {
      Name = "${local.resource_prefix}-operator"
    },
  )
}
