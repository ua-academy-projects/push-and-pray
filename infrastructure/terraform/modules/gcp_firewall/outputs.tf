output "redis_ingress" {
  description = "Private Redis firewall rule metadata for validation and operations."
  value = {
    source_tags   = google_compute_firewall.redis.source_tags
    source_ranges = google_compute_firewall.redis.source_ranges
    target_tags   = google_compute_firewall.redis.target_tags
    ports         = one(google_compute_firewall.redis.allow).ports
  }
}

output "postgresql_ingress_enabled" {
  description = "Whether the infra VM accepts local PostgreSQL traffic."
  value       = length(google_compute_firewall.postgresql) > 0
}
