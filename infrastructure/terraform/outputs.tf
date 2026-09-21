output "gcp_database_connection" {
  description = "Managed GCP database connection metadata, without password values; null outside GCP cloud database mode."
  value       = module.gcp_database.connection
}

locals {
  vm_names = merge(
    { for name, vm in module.gcp_vm.vms : name => vm.name },
    { for name, vm in module.aws_vm.vms : name => vm.name },
  )

  vm_internal_ips = merge(
    { for name, vm in module.gcp_vm.vms : name => vm.internal_ip },
    { for name, vm in module.aws_vm.vms : name => vm.internal_ip },
  )

  vm_public_ips = merge(
    { for name, vm in module.gcp_vm.vms : name => vm.public_ip },
    { for name, vm in module.aws_vm.vms : name => vm.public_ip },
  )
}

output "aws_database_connection" {
  description = "Managed AWS database connection metadata, without password values; null outside AWS cloud database mode."
  value       = module.aws_database.connection
}

output "bastion_public_ip" {
  description = "Bastion public IP."
  value       = local.vm_public_ips["bastion"]
}

output "workload_vm_names" {
  description = "VM names by workload."
  value = {
    for name, workload in local.config.vms : name => local.vm_names[name]
    if workload.role != "bastion"
  }
}

output "workload_roles" {
  description = "Roles by workload."
  value = {
    for name, workload in local.config.vms : name => workload.role
    if workload.role != "bastion"
  }
}

output "workload_internal_ips" {
  description = "Internal IPs by workload."
  value = {
    for name, workload in local.config.vms : name => local.vm_internal_ips[name]
    if workload.role != "bastion"
  }
}

output "workload_external_ips" {
  description = "External IPs by workload."
  value = {
    for name, workload in local.config.vms : name => local.vm_public_ips[name]
    if workload.role != "bastion"
  }
}

output "workload_network_tags" {
  description = "GCP network tags by GCP workload."
  value = {
    for name, vm in module.gcp_vm.vms : name => vm.network_tags
    if local.config.vms[name].role != "bastion"
  }
}

output "workload_service_account_emails" {
  description = "GCP service-account emails by GCP workload."
  value = {
    for name, vm in module.gcp_vm.vms : name => vm.service_account_email
    if local.config.vms[name].role != "bastion"
  }
}

output "secret_ids" {
  description = "Secret container IDs created from the project configuration across all clouds."
  value = sort(distinct(concat(
    module.gcp_secrets.secret_ids,
    module.aws_secrets.secret_ids,
  )))
}

output "secret_resource_names" {
  description = "Fully qualified secret resource names by cloud and secret ID."
  value = {
    gcp = module.gcp_secrets.secret_resource_names
    aws = module.aws_secrets.secret_resource_names
  }
}

output "workload_secret_access" {
  description = "Secret IDs each workload identity may read. Names only - never values."
  value = {
    for name, workload in local.config.vms :
    name => sort(distinct(values(workload.secret_mappings)))
    if workload.role != "bastion"
  }
}

output "budgets" {
  value = { aws = module.aws_budget.summary, gcp = module.gcp_budget.summary }
}

output "dns" {
  description = "The Cloudflare record published for the UI, or null when DNS is managed by hand."
  value       = module.cloudflare_dns.summary
}

output "aws_monitoring" {
  description = "AWS monitoring identifiers and non-secret agent configurations for deployment."
  value = {
    log_group_name           = module.aws_monitoring.log_group_name
    sns_topic_arn            = module.aws_monitoring.sns_topic_arn
    dashboard_name           = module.aws_monitoring.dashboard_name
    alarm_arns               = module.aws_monitoring.alarm_arns
    canary_name              = module.aws_monitoring.canary_name
    agent_configurations     = module.aws_monitoring.agent_configurations
    collector_configurations = module.aws_monitoring.collector_configurations
  }
}

output "gcp_monitoring" {
  description = "GCP monitoring identifiers and Ops Agent YAML for Ansible deployment."
  value = {
    log_bucket_id            = module.gcp_monitoring.log_bucket_id
    log_filter               = module.gcp_monitoring.log_filter
    notification_channel_ids = module.gcp_monitoring.notification_channel_ids
    dashboard_id             = module.gcp_monitoring.dashboard_id
    alert_policy_ids         = module.gcp_monitoring.alert_policy_ids
    uptime_check_id          = module.gcp_monitoring.uptime_check_id
    agent_configurations     = module.gcp_monitoring.agent_configurations
    collector_configurations = module.gcp_monitoring.collector_configurations
  }
}
