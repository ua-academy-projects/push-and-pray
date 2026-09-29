# K3s Ingress role

Exposes the internal OilScope UI Service through K3s's bundled Traefik ingress
controller. The standard Kubernetes Ingress routes the configured application
hostname to `ui:8080` and asks cert-manager's existing
`letsencrypt-production` ClusterIssuer for a browser-trusted certificate.

A namespace-scoped Traefik Middleware permanently redirects normal HTTP
requests to the equivalent HTTPS URL. It is attached only to the OilScope UI
Ingress, so cert-manager's separate temporary HTTP-01 solver Ingress remains
reachable during initial issuance and automatic renewal.

cert-manager's ingress-shim creates a Certificate with the same name as the
configured TLS Secret. The role waits for that Certificate to appear and reach
the `Ready` condition, so a successful play confirms that the public HTTP-01
challenge path, DNS record, GCP passthrough load balancer, Traefik, and Let's
Encrypt are working together.

The role is the final stage of the application deployment playbook:

```bash
ansible-playbook oilscope.platform.deploy_k3s_application \
  -i localhost, \
  -e k3s_application_config_file="$PWD/project-config.json"
```

An HTTP request should return a permanent redirect after reconciliation:

```bash
OILSCOPE_HOSTNAME="$(jq -r '.k3s.application.hostname' project-config.json)"
curl -I "http://${OILSCOPE_HOSTNAME}"
```

The response should redirect to the HTTPS URL for the configured hostname.
