variable "config" {
  description = "Project naming, VM roles and shared monitoring settings."
  type = object({
    name_prefix = string
    environment = string
    clouds      = object({ gcp = optional(object({ project_id = string })) })
    vms         = map(object({ role = string }))
    budgets     = optional(object({ gcp = optional(object({ enabled = optional(bool, false) }), {}) }), {})
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
      application_metrics_enabled     = optional(bool, false)
      service_logs_enabled            = optional(bool, false)
      database_metrics_enabled        = optional(bool, false)
      detailed_monitoring_enabled     = optional(bool, false)
      disk_fstype                     = optional(string, "ext4")
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
  validation {
    condition     = var.config.monitoring.log_retention_days >= 1 && var.config.monitoring.log_retention_days <= 3650 && floor(var.config.monitoring.log_retention_days) == var.config.monitoring.log_retention_days
    error_message = "GCP log retention must be a whole number between 1 and 3650 days."
  }
  validation {
    condition     = alltrue([for n in [var.config.monitoring.cpu_threshold_percent, var.config.monitoring.memory_threshold_percent, var.config.monitoring.disk_threshold_percent] : n > 0 && n <= 100]) && var.config.monitoring.http_error_threshold >= 1 && floor(var.config.monitoring.http_error_threshold) == var.config.monitoring.http_error_threshold
    error_message = "Percentages must be in (0,100]; HTTP threshold must be a positive integer."
  }
  validation {
    condition     = !var.config.monitoring.enabled || (length([for name in keys(var.vms) : name if var.config.vms[name].role != "bastion"]) == 0 && !(var.config.monitoring.database_metrics_enabled && var.database != null) && !var.config.monitoring.synthetics.enabled) || !var.config.monitoring.alarms_enabled || length(var.config.monitoring.email_recipients) > 0
    error_message = "Enabled GCP alarms require email recipients."
  }
  validation {
    condition     = alltrue([for email in var.config.monitoring.email_recipients : can(regex("^[^ @]+@[^ @]+\\.[^ @]+$", email))])
    error_message = "Recipients must be email addresses."
  }
  validation {
    condition     = !var.config.monitoring.enabled || !var.config.monitoring.synthetics.enabled || (contains([5, 10, 15], var.config.monitoring.synthetics.period_minutes) && can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$", var.config.monitoring.synthetics.hostname)) && startswith(var.config.monitoring.synthetics.path, "/"))
    error_message = "GCP uptime checks require a hostname, absolute path and period_minutes of 5, 10 or 15."
  }
  validation {
    condition     = alltrue([for name in keys(var.vms) : contains(keys(var.config.vms), name)]) && (length([for name in keys(var.vms) : name if var.config.vms[name].role != "bastion"]) == 0 || try(length(var.config.clouds.gcp.project_id) > 0, false))
    error_message = "Each GCP VM needs a matching config entry and a GCP project ID."
  }
  validation {
    condition     = var.config.monitoring.synthetics.clouds == null ? true : alltrue([for cloud in var.config.monitoring.synthetics.clouds : contains(["aws", "gcp"], cloud)])
    error_message = "Synthetic clouds must contain only aws or gcp."
  }
  validation {
    condition     = alltrue([for n in [var.config.monitoring.redis_memory_threshold_percent, var.config.monitoring.database_cpu_threshold_percent, var.config.monitoring.database_disk_threshold_percent] : n > 0 && n <= 100]) && alltrue([for n in [var.config.monitoring.outbox_count_threshold, var.config.monitoring.outbox_age_seconds, var.config.monitoring.rabbitmq_queue_threshold, var.config.monitoring.rabbitmq_unacked_threshold, var.config.monitoring.rabbitmq_dead_threshold, var.config.monitoring.freshness_seconds, var.config.monitoring.database_connections_threshold, var.config.monitoring.database_free_storage_bytes] : n > 0])
    error_message = "Application/database percentages must be in (0,100] and thresholds must be positive."
  }
  validation {
    condition     = !(var.config.budgets.gcp.enabled || (var.config.monitoring.enabled && var.config.monitoring.synthetics.enabled && (var.config.monitoring.synthetics.clouds == null ? length([for name in keys(var.vms) : name if var.config.vms[name].role != "bastion"]) > 0 : contains(var.config.monitoring.synthetics.clouds, "gcp")))) || try(length(var.config.clouds.gcp.project_id) > 0, false)
    error_message = "GCP budgets and independently selected uptime checks require clouds.gcp.project_id."
  }

}
variable "vms" {
  description = "GCE outputs keyed by stable VM configuration names."
  type        = map(object({ instance_id = string, zone = string }))

}

variable "database" {
  description = "Managed database identity for native metrics; null in application mode."
  type        = object({ id = string, project_id = optional(string) })
  default     = null
}
