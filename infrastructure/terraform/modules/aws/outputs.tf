output "bastion_public_ips" {
  description = "Public IP of this cloud's bastion, keyed by cloud name. Empty when the cloud is inactive."
  value = {
    for instance in module.bastion : local.this_cloud => instance.public_ip
  }
}

output "workload_vm_names" {
  description = "VM names by workload."
  value = {
    for name, workload in local.workload_vms : name => module.vm[name].name
  }
}

output "workload_roles" {
  description = "Roles by workload."
  value = {
    for name, workload in local.workload_vms : name => workload.role
  }
}

output "workload_clouds" {
  description = "Cloud hosting each workload. Matches the cloud tag the Ansible inventory selects on."
  value = {
    for name, workload in local.workload_vms : name => local.this_cloud
  }
}

output "workload_internal_ips" {
  description = "Internal IPs by workload."
  value = {
    for name, workload in local.workload_vms : name => module.vm[name].internal_ip
  }
}

output "workload_external_ips" {
  description = "External IPs by workload."
  value = {
    for name, workload in local.workload_vms : name => module.vm[name].public_ip
  }
}

output "workload_network_scopes" {
  description = "Security groups each workload belongs to."
  value = {
    for name, workload in local.workload_vms : name => module.vm[name].security_group_ids
  }
}

output "workload_identities" {
  description = "IAM role ARN of each workload."
  value = {
    for name, workload in local.workload_vms : name => module.identity[name].identity
  }
}

output "secret_ids" {
  description = "Secrets Manager secret names created from the project configuration."
  value       = sort(local.all_secret_ids)
}

output "secret_resource_names" {
  description = "Fully qualified Secrets Manager ARNs, by secret name."
  value = {
    for secret_id, secret in aws_secretsmanager_secret.this : secret_id => secret.arn
  }
}

output "workload_secret_access" {
  description = "Secret IDs each workload identity may read. Names only - never values."
  value = {
    for name, workload in local.workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}

output "database" {
  description = "The managed database on this cloud - host, port, names, and the ARN of the secret RDS keeps the master password in - or null when this cloud does not build one. Never a password."
  value = local.builds_database ? {
    mode                = "managed"
    cloud               = local.this_cloud
    host                = module.database[0].host
    port                = module.database[0].port
    name                = module.database[0].name
    username            = var.config.database.username
    instance            = module.database[0].instance_identifier
    password_secret_arn = module.database[0].master_user_secret_arn
  } : null
}
