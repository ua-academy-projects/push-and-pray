output "connection" {
  value = {
    provider                   = "pubsub"
    project_id                 = var.project_id
    topic_id                   = google_pubsub_topic.events.name
    subscription_id            = google_pubsub_subscription.history.name
    visibility_timeout_seconds = var.settings.visibility_timeout_seconds
  }
}
