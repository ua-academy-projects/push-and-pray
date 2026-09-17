variable "config" {
  description = "Project naming, region, VM roles, and optional monitoring settings."
  type = object({
    name_prefix = string
    environment = string
    region      = string
    region_map  = map(object({ aws = object({ region = string }) }))
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
        runtime_version = optional(string, "syn-nodejs-puppeteer-17.0")
      }), {})
    }), {})
  })
  validation {
    condition     = !var.config.monitoring.synthetics.browser_enabled || (var.config.monitoring.synthetics.period_minutes >= 3 && (var.config.monitoring.synthetics.clouds == null ? true : contains(var.config.monitoring.synthetics.clouds, "aws")))
    error_message = "Browser journeys require AWS synthetics and a period of at least 3 minutes; the target app may run in either cloud."
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
    condition     = !var.config.monitoring.enabled || !var.config.monitoring.alarms_enabled || length(var.config.monitoring.email_recipients) > 0
    error_message = "Enabled AWS alarms require email recipients."
  }
  validation {
    condition     = alltrue([for email in var.config.monitoring.email_recipients : can(regex("^[^ @]+@[^ @]+\\.[^ @]+$", email))])
    error_message = "Recipients must be email addresses."
  }
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.config.monitoring.log_retention_days)
    error_message = "Choose a supported CloudWatch Logs retention period."
  }
  validation {
    condition     = alltrue([for n in [var.config.monitoring.cpu_threshold_percent, var.config.monitoring.memory_threshold_percent, var.config.monitoring.disk_threshold_percent] : n > 0 && n <= 100]) && var.config.monitoring.http_error_threshold >= 1 && floor(var.config.monitoring.http_error_threshold) == var.config.monitoring.http_error_threshold
    error_message = "Percentages must be in (0,100]; HTTP threshold must be a positive integer."
  }
  validation {
    condition     = !var.config.monitoring.enabled || !var.config.monitoring.synthetics.enabled || (var.config.monitoring.synthetics.period_minutes >= 1 && var.config.monitoring.synthetics.period_minutes <= 60 && floor(var.config.monitoring.synthetics.period_minutes) == var.config.monitoring.synthetics.period_minutes && can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$", var.config.monitoring.synthetics.hostname)) && startswith(var.config.monitoring.synthetics.path, "/"))
    error_message = "AWS synthetics require a hostname, absolute path and integer period of 1–60 minutes."
  }

}

variable "vms" {
  description = "Created AWS instances keyed by VM configuration name."
  type        = map(object({ instance_id = string }))
  validation {
    condition     = alltrue([for name in keys(var.vms) : contains(keys(var.config.vms), name)])
    error_message = "Every VM output must have a matching config.vms entry."
  }
}

variable "database" {
  description = "Managed database identity for native metrics; null in application mode."
  type        = object({ id = string, project_id = optional(string) })
  default     = null
}
