resource "google_project_iam_member" "log_writer" {
  for_each = var.identities

  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = each.value
}

# The bucket every entry lands in unless a sink says otherwise. It always
# exists; this only sets how long it keeps what the agents send.
resource "google_logging_project_bucket_config" "default" {
  project        = var.project_id
  location       = "global"
  bucket_id      = "_Default"
  retention_days = var.retention_days
}
