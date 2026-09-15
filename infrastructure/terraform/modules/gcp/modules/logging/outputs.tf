output "log_name" {
  description = "Log the Ops Agent's journald receiver writes to. Alert filters start from it."
  value       = "projects/${var.project_id}/logs/journald"
}
