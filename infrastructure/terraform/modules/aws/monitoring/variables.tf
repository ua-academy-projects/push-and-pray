variable "config" {
  description = "Project naming, region, VM roles, and optional monitoring settings."
  type = object({
    name_prefix = string
    environment = string
    region      = string
    region_map  = map(object({ aws = object({ region = string }) }))
    vms         = map(object({ role = string }))
    monitoring = optional(object({
      enabled                  = optional(bool, true)
      email_recipients         = optional(set(string), [])
      logs_enabled             = optional(bool, true)
      alarms_enabled           = optional(bool, false)
      dashboard_enabled        = optional(bool, false)
      agent_metrics_enabled    = optional(bool, false)
      log_retention_days       = optional(number, 7)
      cpu_threshold_percent    = optional(number, 80)
      memory_threshold_percent = optional(number, 85)
      disk_threshold_percent   = optional(number, 85)
      http_error_threshold     = optional(number, 1)
      disk_fstype              = optional(string, "ext4")
      synthetics = optional(object({
        enabled         = optional(bool, false)
        hostname        = optional(string, "")
        path            = optional(string, "/health")
        period_minutes  = optional(number, 5)
        runtime_version = optional(string, "syn-nodejs-puppeteer-17.0")
      }), {})
    }), {})
  })
}

variable "vms" {
  description = "Created AWS instances keyed by VM configuration name."
  type        = map(object({ instance_id = string }))
  validation {
    condition     = alltrue([for name in keys(var.vms) : contains(keys(var.config.vms), name)])
    error_message = "Every VM output must have a matching config.vms entry."
  }
}
