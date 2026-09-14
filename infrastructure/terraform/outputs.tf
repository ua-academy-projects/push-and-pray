output "bastion_public_ip" {
  description = "Bastion public IP regardless of cloud provider."

  value = (
    local.bastion_vm.cloud == "gcp"
    ? module.vm.vms["bastion"].public_ip
    : module.aws_vm.vms["bastion"].public_ip
  )
}

output "workload_vm_names" {
  description = "VM names by workload regardless of cloud provider."

  value = {
    for name, workload in local.workload_vms :
    name => (
      workload.cloud == "gcp"
      ? module.vm.vms[name].name
      : module.aws_vm.vms[name].name
    )
  }
}

output "workload_roles" {
  description = "Functional roles by workload."

  value = {
    for name, workload in local.workload_vms :
    name => workload.role
  }
}

output "workload_clouds" {
  description = "Cloud provider used by each workload."

  value = {
    for name, workload in local.workload_vms :
    name => workload.cloud
  }
}

output "workload_internal_ips" {
  description = "Internal IP addresses by workload."

  value = {
    for name, workload in local.workload_vms :
    name => (
      workload.cloud == "gcp"
      ? module.vm.vms[name].internal_ip
      : module.aws_vm.vms[name].internal_ip
    )
  }
}

output "workload_external_ips" {
  description = "External IP addresses by workload."

  value = {
    for name, workload in local.workload_vms :
    name => (
      workload.cloud == "gcp"
      ? module.vm.vms[name].public_ip
      : module.aws_vm.vms[name].public_ip
    )
  }
}

output "workload_network_tags" {
  description = "GCP network tags by workload. AWS workloads return an empty list."

  value = {
    for name, workload in local.workload_vms :
    name => (
      workload.cloud == "gcp"
      ? module.vm.vms[name].network_tags
      : []
    )
  }
}

output "workload_aws_tags" {
  description = "AWS tags by workload. GCP workloads return an empty map."

  value = {
    for name, workload in local.workload_vms :
    name => (
      workload.cloud == "aws"
      ? module.aws_vm.vms[name].tags
      : {}
    )
  }
}

output "workload_service_account_emails" {
  description = "GCP service-account emails by GCP workload."

  value = {
    for name, workload in local.gcp_workload_vms :
    name => module.vm.vms[name].service_account_email
  }
}

output "workload_iam_role_arns" {
  description = "AWS IAM role ARNs by AWS workload."

  value = {
    for name, workload in local.aws_workload_vms :
    name => module.aws_vm.vms[name].iam_role_arn
  }
}

output "secret_ids" {
  description = "Logical secret container IDs used across configured clouds."

  value = sort(
    distinct(
      concat(
        local.gcp_secret_ids,
        local.aws_secret_ids,
      )
    )
  )
}

output "secret_resource_names" {
  description = "Secret resource identifiers grouped by cloud provider."

  value = {
    gcp = {
      for secret_id, secret in google_secret_manager_secret.this :
      secret_id => secret.name
    }

    aws = {
      for secret_id, secret in aws_secretsmanager_secret.this :
      secret_id => secret.arn
    }
  }
}

output "workload_secret_access" {
  description = "Logical secret IDs each workload may read. Values are never exposed."

  value = {
    for name, workload in local.workload_vms :
    name => sort(
      distinct(
        values(local.effective_secret_mappings[workload.role])
      )
    )
  }
}

output "resolved_vm_configuration" {
  description = "Provider-neutral and resolved placement values for validation and operations."

  value = {
    for name, vm in merge(module.vm.resolved_vms, module.aws_vm.resolved_vms) : name => {
      role               = vm.role
      cloud              = vm.cloud
      logical_region     = vm.region_key
      provider_region    = vm.provider_region
      provider_zone      = vm.provider_zone
      logical_size       = vm.size
      provider_size      = vm.machine_type
      logical_disk_type  = vm.boot_disk.type
      provider_disk_type = vm.disk_type
      assign_public_ip   = vm.assign_public_ip
    }
  }
}

output "monitoring_status" {
  description = "Enabled provider monitoring and the Terraform-managed VM names it covers."
  value = {
    gcp = {
      enabled          = module.gcp_monitoring.enabled
      http_5xx_enabled = module.gcp_monitoring.http_5xx_enabled
      vm_names         = module.gcp_monitoring.monitored_vm_names
    }
    aws = {
      enabled          = module.aws_monitoring.enabled
      http_5xx_enabled = module.aws_monitoring.http_5xx_enabled
      vm_names         = module.aws_monitoring.monitored_vm_names
    }
  }
}

output "database_connection" {
  description = "Provider-neutral database connection metadata. Passwords are intentionally excluded."
  value = {
    mode  = local.database_mode
    cloud = local.database_mode == "managed" ? local.managed_cloud : local.vms.infra.cloud
    host = local.database_mode == "managed" ? try(
      module.gcp_managed_database[0].host,
      module.aws_managed_database[0].host,
      null,
      ) : (
      local.vms.infra.cloud == "gcp"
      ? module.vm.vms.infra.internal_ip
      : module.aws_vm.vms.infra.internal_ip
    )
    port = local.database_port
    name = local.database_name
  }
}

output "redis_connection" {
  description = "Provider-neutral Redis connection metadata. The password is intentionally excluded."
  value = {
    host = (
      local.vms.infra.cloud == "gcp"
      ? module.vm.vms.infra.internal_ip
      : module.aws_vm.vms.infra.internal_ip
    )
    port = local.redis_port
  }
}

output "redis_network_policy" {
  description = "Provider Redis ingress policy; only the UI workload may connect to the infra VM."
  value = {
    gcp = length(module.gcp_firewall) > 0 ? module.gcp_firewall[0].redis_ingress : null
    aws = length(module.aws_security_groups) > 0 ? module.aws_security_groups[0].redis_ingress : null
  }
}
