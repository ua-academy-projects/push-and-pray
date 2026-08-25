terraform {
  # Bucket and prefix are intentionally supplied at init time from the
  # external project JSON. Credentials and secret values must never be passed
  # through backend configuration.
  backend "gcs" {}
}
