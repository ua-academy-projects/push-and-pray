output "destination" {
  description = "Cloud Monitoring and Logging destination configured for VM agents."
  value = {
    metrics_scope = "project"
    log_bucket    = google_logging_project_bucket_config.default.bucket_id
  }
}
