variable "config" {
  description = "Project naming, VM roles, and optional monitoring settings."
  type = object({
    name_prefix = string
    environment = string
    vms         = map(object({ role = string }))
    monitoring = optional(object({
      enabled                         = optional(bool, true)
      email_recipients                = optional(set(string), [])
      logs_enabled                    = optional(bool, true)
      alarms_enabled                  = optional(bool, false)
      dashboard_enabled               = optional(bool, false)
      agent_metrics_enabled           = optional(bool, false)
      log_retention_days              = optional(number, 7)
      cpu_threshold_percent           = optional(number, 80)
      memory_threshold_percent        = optional(number, 85)
      disk_threshold_percent          = optional(number, 85)
      http_error_threshold            = optional(number, 1)
      disk_fstype                     = optional(string, "ext4")
      application_metrics_enabled     = optional(bool, false)
      service_logs_enabled            = optional(bool, false)
      database_metrics_enabled        = optional(bool, false)
      detailed_monitoring_enabled     = optional(bool, false)
      outbox_count_threshold          = optional(number, 100)
      outbox_age_seconds              = optional(number, 600)
      rabbitmq_queue_threshold        = optional(number, 1000)
      rabbitmq_unacked_threshold      = optional(number, 100)
      rabbitmq_dead_threshold         = optional(number, 1)
      redis_memory_threshold_percent  = optional(number, 85)
      freshness_seconds               = optional(number, 28800)
      database_connections_threshold  = optional(number, 80)
      database_free_storage_bytes     = optional(number, 1073741824)
      database_cpu_threshold_percent  = optional(number, 80)
      database_disk_threshold_percent = optional(number, 85)
      synthetics = optional(object({
        browser_enabled = optional(bool, false)
        clouds          = optional(set(string))
        enabled         = optional(bool, false)
        hostname        = optional(string, "")
        path            = optional(string, "/health")
        period_minutes  = optional(number, 5)
      }), {})
    }), {})
  })
}

variable "network" {
  description = "Outputs of the azure_network module; the workspace and rules live in the same resource group."
  type = object({
    resource_group_name = string
    location            = string
  })
}

variable "vms" {
  description = "Created Azure VMs keyed by VM configuration name; the agent attaches to the VM through its own managed identity."
  type = map(object({
    instance_id          = string
    identity_client_id   = string
    identity_resource_id = string
  }))
}

variable "database" {
  description = "Managed database identity for native metrics; null in application mode."
  type        = object({ id = string })
  default     = null
}
