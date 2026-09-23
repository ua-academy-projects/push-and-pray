# History role

Deploys the History container and validates its local health endpoint.

The role requires PostgreSQL and RabbitMQ connection settings. Their endpoints
come from Terraform's `service_endpoints` output; passwords come from the
cloud secrets mapped as `POSTGRES_PASSWORD` and `RABBITMQ_PASSWORD`.

History is the only application service with direct PostgreSQL access.
