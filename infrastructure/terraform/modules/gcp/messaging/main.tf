locals {
  topic_name       = "${var.resource_prefix}-${var.settings.queue_name}"
  dead_letter_name = "${local.topic_name}-dead-letter"
}

resource "google_pubsub_topic" "events" {
  name   = local.topic_name
  labels = var.labels
}

resource "google_pubsub_topic" "dead_letter" {
  name   = local.dead_letter_name
  labels = var.labels
}

resource "google_pubsub_subscription" "history" {
  name                       = "${local.topic_name}-history"
  topic                      = google_pubsub_topic.events.id
  ack_deadline_seconds       = var.settings.visibility_timeout_seconds
  message_retention_duration = "1209600s"

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = var.settings.max_delivery_attempts
  }
}

resource "google_pubsub_topic_iam_member" "fetcher_publish" {
  topic  = google_pubsub_topic.events.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${var.publisher_service_account_email}"
}

resource "google_pubsub_subscription_iam_member" "history_consume" {
  subscription = google_pubsub_subscription.history.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.consumer_service_account_email}"
}
