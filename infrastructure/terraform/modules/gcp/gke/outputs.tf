output "managed_kubernetes" {
  value = local.enabled ? {
    cloud          = "gcp"
    name           = google_container_cluster.main[0].name
    region         = local.region
    zone           = google_container_cluster.main[0].location
    resource_group = null
    project        = local.project_id
  } : null
}
