# Commented with the GCP modules in main.tf; uncomment together with them.
# output "gcp_database_connection" {
#   description = "Managed GCP database connection metadata, without password values; null outside GCP cloud database mode."
#   value       = module.gcp_database.connection
# }

# Commented with the Azure modules in main.tf; uncomment together with them.
# output "azure_database_connection" {
#   description = "Managed Azure database connection metadata, without password values; null outside Azure cloud database mode."
#   value       = module.azure_database.connection
# }

output "aws_database_connection" {
  description = "Managed AWS database connection metadata, without password values; null outside AWS cloud database mode."
  value       = module.aws_database.connection
}

output "cluster" {
  description = "The cluster as deployed, for whichever Kubernetes platform managed_kubernetes selected. On k3s: the three nodes and the names that resolve to the entry node. On EKS: the endpoint and cluster name AWS publishes, with no nodes and no entry node, because no single machine receives traffic. Ansible reads this from an exported terraform-outputs.json, so a stale export silently feeds old addresses."
  value = {
    platform     = module.aws_eks.enabled ? "eks" : "k3s"
    ingress_host = local.config.ingress.hostname
    namespace    = local.config.kubernetes.namespace
    region       = local.config.region_map[local.config.region].aws.region

    entry_node = module.aws_eks.enabled ? null : try(local.config.kubernetes.entry_node, null)
    api_endpoint = (
      module.aws_eks.enabled
      ? module.aws_eks.endpoint
      : try(local.config.kubernetes.api_endpoint, null)
    )

    nodes = {
      for name, vm in module.aws_vm.vms : name => {
        name        = vm.name
        instance_id = vm.instance_id
        internal_ip = vm.internal_ip
        public_ip   = vm.public_ip
        roles       = local.config.vms[name].network_tags
      }
    }

    eks = module.aws_eks.enabled ? {
      cluster_name               = module.aws_eks.cluster_name
      endpoint                   = module.aws_eks.endpoint
      certificate_authority_data = module.aws_eks.certificate_authority_data
      node_group_name            = module.aws_eks.node_group_name
      vpc_id                     = module.aws_eks.vpc_id
      cluster_security_group_id  = module.aws_eks.cluster_security_group_id
      oidc_identity_provider     = module.aws_eks.oidc_identity_provider
    } : null
  }
}

output "secret_ids" {
  description = "Secret container IDs created from the project configuration across all clouds."
  value = sort(distinct(concat(
    module.aws_secrets.secret_ids,
    # module.gcp_secrets.secret_ids,
    # module.azure_secrets.secret_ids,
  )))
}

output "secret_resource_names" {
  description = "Fully qualified secret resource names by cloud and secret ID. Azure entries are versionless Key Vault URIs; the ARM scope a grant uses is not the same string."
  value = {
    aws = module.aws_secrets.secret_resource_names
    # gcp   = module.gcp_secrets.secret_resource_names
    # azure = module.azure_secrets.secret_resource_names
  }
}

output "workload_secret_access" {
  description = "Secret IDs each workload may read, by workload. Resolved by the operator at deployment time and written into namespace-scoped Kubernetes Secrets. Names only - never values."
  value = {
    for workload, mappings in local.config.secret_mappings :
    workload => sort(distinct(values(mappings)))
  }
}

output "budgets" {
  value = { aws = module.aws_budget.summary }
}

output "dns" {
  description = "The Cloudflare records published for the entry node, or null when DNS is managed by hand."
  value       = module.cloudflare_dns.summary
}

output "headlamp" {
  description = "The operator console's resolved hostname and the entry-node address it points at. Ansible reads this to decide whether to deploy the console; no credential appears here."
  value       = module.cloudflare_dns.headlamp
}

output "registry" {
  description = "Container repository URLs and the immutable image reference to deploy for each service."
  value       = module.aws_registry.repositories
}

output "registry_publisher_role_arn" {
  description = "Role GitHub Actions assumes to push images, for the workflow's aws-actions/configure-aws-credentials step."
  value       = module.aws_registry.publisher_role_arn
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

# output "gcp_monitoring" {
#   description = "GCP monitoring identifiers and Ops Agent YAML for Ansible deployment."
#   value = {
#     log_bucket_id            = module.gcp_monitoring.log_bucket_id
#     log_filter               = module.gcp_monitoring.log_filter
#     notification_channel_ids = module.gcp_monitoring.notification_channel_ids
#     dashboard_id             = module.gcp_monitoring.dashboard_id
#     alert_policy_ids         = module.gcp_monitoring.alert_policy_ids
#     uptime_check_id          = module.gcp_monitoring.uptime_check_id
#     agent_configurations     = module.gcp_monitoring.agent_configurations
#     collector_configurations = module.gcp_monitoring.collector_configurations
#   }
# }

# output "azure_monitoring" {
#   description = "Azure monitoring identifiers and non-secret agent wiring for deployment."
#   value = {
#     workspace_id             = module.azure_monitoring.workspace_id
#     action_group_id          = module.azure_monitoring.action_group_id
#     workbook_id              = module.azure_monitoring.workbook_id
#     availability_test_id     = module.azure_monitoring.availability_test_id
#     alert_ids                = module.azure_monitoring.alert_ids
#     agent_configurations     = module.azure_monitoring.agent_configurations
#     collector_configurations = module.azure_monitoring.collector_configurations
#   }
# }
#
# output "azure_deployment" {
#   description = "Non-secret Azure deployment provenance and the managed identity each workload runs as; the inventory plugin scopes its discovery from the project configuration, not from here."
#   value = {
#     subscription_id     = try(local.config.clouds.azure.subscription_id, null)
#     resource_group_name = module.azure_network.resource_group_name
#     location            = module.azure_network.location
#     key_vault           = module.azure_secrets.vault
#     identities = {
#       for name, vm in module.azure_vm.vms : name => {
#         client_id   = vm.identity_client_id
#         resource_id = vm.identity_resource_id
#       }
#     }
#   }
# }
