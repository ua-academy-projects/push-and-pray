output "bastion_public_ips" {
  description = "Public IP of this cloud's bastion, keyed by cloud name. Empty when the cloud is inactive."
  value = {
    for instance in module.bastion : local.this_cloud => instance.public_ip
  }
}

output "bastion_internal_ips" {
  description = "Internal IP of this cloud's bastion, keyed by cloud name. Empty when the cloud is inactive."
  value = {
    for instance in module.bastion : local.this_cloud => instance.internal_ip
  }
}

output "node_vm_names" {
  description = "VM names by node."
  value = {
    for name, node in local.nodes : name => module.vm[name].name
  }
}

output "node_roles" {
  description = "k3s role by node."
  value = {
    for name, node in local.nodes : name => node.role
  }
}

output "node_clouds" {
  description = "Cloud hosting each node. Matches the cloud label the Ansible inventory selects on."
  value = {
    for name, node in local.nodes : name => local.this_cloud
  }
}

output "node_internal_ips" {
  description = "Internal IPs by node, as AWS assigned them."
  value = {
    for name, node in local.nodes : name => module.vm[name].internal_ip
  }
}

output "node_external_ips" {
  description = "External IPs by node."
  value = {
    for name, node in local.nodes : name => module.vm[name].public_ip
  }
}

output "node_identities" {
  description = "IAM role ARN of each node."
  value = {
    for name, node in local.nodes : name => module.identity[name].identity
  }
}

output "secret_ids" {
  description = "Secrets Manager secret names this cloud holds."
  value       = local.secret_ids
}

output "secret_resource_names" {
  description = "Fully qualified Secrets Manager ARNs, by secret name."
  value = {
    for secret_id, secret in aws_secretsmanager_secret.this : secret_id => secret.arn
  }
}

output "node_secret_access" {
  description = "Secret IDs each k3s_server node may read. Names only - never values."
  value = {
    for name in local.server_nodes : name => local.secret_ids
  }
}
