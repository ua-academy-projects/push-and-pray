locals {
  agent_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  grants = {
    for pair in setproduct(keys(var.service_account_emails), local.agent_roles) :
    "${pair[0]}/${pair[1]}" => {
      account_name = pair[0]
      role         = pair[1]
    }
  }
}
