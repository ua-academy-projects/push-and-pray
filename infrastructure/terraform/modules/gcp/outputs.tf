output "vms" {
  description = "Provider-neutral GCP VM records."
  value = {
    for name, vm in module.vm : name => {
      contract_version = 1
      logical_name     = name
      name             = vm.name
      role             = module.config.provisionable_vms[name].role
      provider         = module.config.cloud
      cloud            = module.config.cloud
      region           = module.config.location.region
      zone             = module.config.location.zone
      architecture     = try(module.config.provisionable_vms[name].architecture, "amd64")
      private_address  = vm.internal_ip
      public_address   = vm.public_ip
      internal_ip      = vm.internal_ip
      public_ip        = vm.public_ip
      network_tags     = vm.network_tags
      runtime_identity = vm.service_account_email
      access_profiles  = toset([module.config.provisionable_vms[name].role])
      labels           = module.config.provisionable_vms[name].metadata
      disks = [{
        id      = vm.boot_disk_id
        purpose = "boot"
      }]
      ssh = {
        user = keys(module.config.config.ssh_users)[0]
        port = try(module.config.provisionable_vms[name].ssh_port, 22)
        proxyjump_node = (
          module.config.provisionable_vms[name].role == "bastion" ? null : module.config.bastion_key
        )
        host_key_alias = "${module.config.resource_prefix}-${name}"
      }
    }
  }
}

output "configuration_valid" {
  description = "Whether every selected profile, cloud override, and GCP location resolves."
  value       = module.config.configuration_valid
}

output "secret_ids" {
  value = sort(module.config.all_secret_ids)
}

output "secret_resource_names" {
  value = {
    for secret_id, secret in google_secret_manager_secret.this :
    secret_id => secret.name
  }
}

output "workload_secret_access" {
  value = {
    for name, workload in module.config.workload_vms :
    name => sort(distinct(values(workload.secret_mappings)))
  }
}

output "managed_database" {
  value = module.config.managed_database_enabled ? merge(module.database[0].connection, {
    enabled = true
    cloud   = "gcp"
  }) : null
}

output "network" {
  value = try({
    network_id = module.network[0].network_id
    vpc_cidr   = module.config.network.vpc_cidr
    region     = module.config.location.region
  }, null)
}

output "managed_service_images" {
  value = try(module.config.manage_db ? {
    cloud    = "gcp"
    registry = "${module.config.location.region}-docker.pkg.dev"
    redis    = "${module.config.location.region}-docker.pkg.dev/${module.config.cloud_config.project_id}/${google_artifact_registry_repository.managed_services[0].repository_id}/redis:${module.config.config.managed_services.redis.target_tag}"
    rabbitmq = "${module.config.location.region}-docker.pkg.dev/${module.config.cloud_config.project_id}/${google_artifact_registry_repository.managed_services[0].repository_id}/rabbitmq:${module.config.config.managed_services.rabbitmq.target_tag}"
  } : null, null)
}

output "application_images" {
  description = "Immutable cloud-registry references for first-party images."
  value = try({
    for service in ["fetcher", "history", "ui", "database"] :
    service => "${module.config.location.region}-docker.pkg.dev/${module.config.cloud_config.project_id}/${google_artifact_registry_repository.application[0].repository_id}/${service}:${module.config.config.registry.image_sha}"
  }, {})
}

output "registry" {
  description = "Provider-neutral registry promotion and runtime contract."
  value = {
    provider       = "gcp"
    host           = "${module.config.location.region}-docker.pkg.dev"
    immutable_tags = true
    application = try({
      for service in ["fetcher", "history", "ui", "database"] :
      service => "${module.config.location.region}-docker.pkg.dev/${module.config.cloud_config.project_id}/${google_artifact_registry_repository.application[0].repository_id}/${service}:${module.config.config.registry.image_sha}"
    }, {})
    managed = try(module.config.manage_db ? {
      redis    = "${module.config.location.region}-docker.pkg.dev/${module.config.cloud_config.project_id}/${google_artifact_registry_repository.managed_services[0].repository_id}/redis:${module.config.config.managed_services.redis.target_tag}"
      rabbitmq = "${module.config.location.region}-docker.pkg.dev/${module.config.cloud_config.project_id}/${google_artifact_registry_repository.managed_services[0].repository_id}/rabbitmq:${module.config.config.managed_services.rabbitmq.target_tag}"
    } : {}, {})
  }
}

output "monitoring" {
  description = "Provider-neutral monitoring resource identifiers."
  value = try(module.observability[0].contract, {
    dashboard_id     = null
    alert_policy_ids = []
    availability_id  = null
    log_metric_ids   = []
  })
}
