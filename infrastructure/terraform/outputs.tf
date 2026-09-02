output "bastion_public_ip" {
  description = "Bastion public IP regardless of cloud provider."

  value = (
    local.bastion_vm.cloud == "gcp"
    ? module.vm["bastion"].public_ip
    : module.aws_vm["bastion"].public_ip
  )
}

output "workload_vm_names" {
  description = "VM names by workload regardless of cloud provider."

  value = {
    for name, workload in local.workload_vms :
    name => (
      workload.cloud == "gcp"
      ? module.vm[name].name
      : module.aws_vm[name].name
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
      ? module.vm[name].internal_ip
      : module.aws_vm[name].internal_ip
    )
  }
}

output "workload_external_ips" {
  description = "External IP addresses by workload."

  value = {
    for name, workload in local.workload_vms :
    name => (
      workload.cloud == "gcp"
      ? module.vm[name].public_ip
      : module.aws_vm[name].public_ip
    )
  }
}

output "workload_network_tags" {
  description = "GCP network tags by workload. AWS workloads return an empty list."

  value = {
    for name, workload in local.workload_vms :
    name => (
      workload.cloud == "gcp"
      ? module.vm[name].network_tags
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
      ? module.aws_vm[name].tags
      : {}
    )
  }
}

output "workload_service_account_emails" {
  description = "GCP service-account emails by GCP workload."

  value = {
    for name, workload in local.gcp_workload_vms :
    name => module.vm[name].service_account_email
  }
}

output "workload_iam_role_arns" {
  description = "AWS IAM role ARNs by AWS workload."

  value = {
    for name, workload in local.aws_workload_vms :
    name => module.aws_vm[name].iam_role_arn
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
        values(workload.secret_mappings)
      )
    )
  }
}