resource "aws_cloudwatch_log_group" "traefik" {
  count             = local.logs_enabled ? 1 : 0
  name              = local.log_group_name
  retention_in_days = local.settings.log_retention_days
  tags              = local.common_labels
}

resource "aws_cloudwatch_log_metric_filter" "http" {
  for_each       = local.logs_enabled ? local.http_filters : {}
  name           = "${local.resource_prefix}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.traefik[0].name
  pattern        = each.value
  metric_transformation {
    name          = each.key
    namespace     = local.http_namespace
    value         = "1"
    default_value = 0
    unit          = "Count"
  }
}
