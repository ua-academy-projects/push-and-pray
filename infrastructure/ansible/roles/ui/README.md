# UI role

Deploys the UI container and waits for its Docker health check.

The role resolves the History VM through inventory and Redis through
Terraform's `service_endpoints` output. The Redis password comes from the
cloud secret mapped as `REDIS_PASSWORD`. UI has no direct PostgreSQL access.
