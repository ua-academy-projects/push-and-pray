output "cluster" {
  value = {
    cloud      = "gcp"
    name       = google_container_cluster.main.name
    region     = google_container_cluster.main.location
    project_id = google_container_cluster.main.project
  }
  depends_on = [google_container_node_pool.main]
}
