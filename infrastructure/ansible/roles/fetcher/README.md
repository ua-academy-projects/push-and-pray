# Fetcher role

Deploys the Fetcher container and waits for its Docker health check.

The role requires an existing Compose file, `fetcher_oilpriceapi_key`, and
RabbitMQ connection settings. The deployment playbook takes the endpoint from
Terraform's `service_endpoints` output and the password from the cloud secret
mapped as `RABBITMQ_PASSWORD`.

The role is idempotent: Compose reconciles the existing container and the
health check confirms that the service is ready.
