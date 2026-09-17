locals {
  raw_config = jsondecode(file(var.project_config_path))
  # Normalize optional settings once so VM permissions and both cloud modules agree.
  config = merge(local.raw_config, {
    monitoring = merge({
      "enabled" : true,
      "logs_enabled" : true,
      "alarms_enabled" : false,
      "dashboard_enabled" : false,
      "agent_metrics_enabled" : false,
      "application_metrics_enabled" : false,
      "service_logs_enabled" : false,
      "database_metrics_enabled" : false,
      "detailed_monitoring_enabled" : false,
      "email_recipients" : [],
      "log_retention_days" : 7,
      "cpu_threshold_percent" : 80,
      "memory_threshold_percent" : 85,
      "disk_threshold_percent" : 85,
      "http_error_threshold" : 1,
      "disk_fstype" : "ext4",
      "outbox_count_threshold" : 100,
      "outbox_age_seconds" : 600,
      "rabbitmq_queue_threshold" : 1000,
      "rabbitmq_unacked_threshold" : 100,
      "rabbitmq_dead_threshold" : 1,
      "redis_memory_threshold_percent" : 85,
      "freshness_seconds" : 28800,
      "database_connections_threshold" : 80,
      "database_free_storage_bytes" : 1073741824,
      "database_cpu_threshold_percent" : 80,
      "database_disk_threshold_percent" : 85
      }, try(local.raw_config.monitoring, {}), {
      synthetics = merge({
        "enabled" : false,
        "hostname" : "oilscope.example.com",
        "path" : "/health",
        "period_minutes" : 5,
        "runtime_version" : "syn-nodejs-puppeteer-17.0",
        "clouds" : null,
        "browser_enabled" : false
      }, try(local.raw_config.monitoring.synthetics, {}))
    })
  })
}
