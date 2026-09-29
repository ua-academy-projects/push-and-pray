# K3s application role

Deploys the OilScope History, Fetcher, and UI workloads as plain Kubernetes
Deployments. History and UI receive internal `ClusterIP` Services because
other components connect to them. Fetcher only initiates outbound work, so it
does not expose an unused inbound Service. The local Ansible controller renders
repository-owned manifests and reconciles them with `kubernetes.core.k8s`; the
application is intentionally not packaged as a Helm chart.

All three workloads use the configured immutable application image tag and the
`<name-prefix>-registry` pull Secret. Credentials are referenced from the
`<name-prefix>-application` Secret and are not rendered into the manifests.
The generated connection URLs use Kubernetes dependent environment-variable
expansion. Passwords generated as hexadecimal strings by the documented secret
workflow are safe in those URLs.

History connects to the internal PostgreSQL and RabbitMQ Services. Fetcher
publishes OilPriceAPI observations to RabbitMQ, and UI reads History through
its internal Service while storing sessions in Redis. The History Service uses
the configured `service_ports.history_api` value and targets the image's fixed
port 8001. HTTP startup and readiness probes check dependencies; TCP liveness
probes only check whether the application process is accepting connections,
avoiding restart cascades during a transient dependency outage.

The deployment playbook runs the existing Kubernetes migration Job first and
only deploys the application after it succeeds:

```bash
ansible-playbook oilscope.platform.deploy_k3s_application \
  -i localhost, \
  -e k3s_application_config_file="$PWD/project-config.json"
```

This role does not create a public Ingress. Add and verify the Ingress after
the three internal workloads are healthy.
