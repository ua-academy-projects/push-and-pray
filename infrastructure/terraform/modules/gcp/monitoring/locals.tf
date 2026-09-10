locals {
  monitoring_enabled = length(var.vms) > 0
  budget_enabled     = try(var.config.monitoring.monthly_budget.gcp_billing_account_id, "") != ""
}
