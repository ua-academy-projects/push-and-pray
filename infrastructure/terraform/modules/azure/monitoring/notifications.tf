resource "azurerm_monitor_action_group" "alerts" {
  count = local.notifications_enabled ? 1 : 0

  name                = "${local.resource_prefix}-monitoring"
  resource_group_name = var.network.resource_group_name
  short_name          = substr(local.resource_prefix, 0, 12)
  tags                = local.common_tags

  dynamic "email_receiver" {
    for_each = local.recipients
    content {
      name                    = replace(email_receiver.value, "@", "-at-")
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}
