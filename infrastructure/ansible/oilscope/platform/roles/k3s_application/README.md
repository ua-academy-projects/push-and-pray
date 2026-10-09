# k3s_application

Deploys OilScope to an initialized K3s cluster. The role:

- creates Kubernetes runtime and private-GHCR pull Secrets without writing
  plaintext credentials to disk;
- installs the pinned official cert-manager chart through the K3s Helm controller;
- uses a Cloudflare DNS-01 challenge to obtain a Let's Encrypt certificate;
- deploys RabbitMQ with persistent storage;
- deploys Redis with persistent storage for UI sessions;
- runs the database image as a migration Job;
- deploys History, Fetcher and UI with health probes;
- deploys plain NGINX on the public agent as the HTTPS reverse proxy;
- reloads NGINX when cert-manager renews the certificate.

Traefik and Caddy are not used. The role expects resolved application secrets,
managed PostgreSQL or CloudNativePG connection metadata, one public endpoint
and the Cloudflare API token from the ignored project configuration.
