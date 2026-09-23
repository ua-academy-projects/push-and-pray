resource "aws_route53_health_check" "ui" {
  for_each = local.ui_vms

  fqdn              = var.config.vms[each.key].public_endpoint.domain
  port              = 443
  type              = "HTTPS"
  resource_path     = var.config.monitoring.ui_health_path
  request_interval  = 30
  failure_threshold = 3
  enable_sni        = true

  tags = merge(var.config.common_labels, {
    Name        = "${local.resource_prefix}-ui-availability"
    environment = var.config.environment
    managed_by  = "terraform"
  })
}
