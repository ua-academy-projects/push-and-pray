# Kubernetes Traefik role

Runs on the local Ansible controller. In self-managed mode it customizes the
K3s-managed Traefik chart with a `HelmChartConfig`, schedules one anti-affined
replica on every configured `k3s-agent`, and changes the Service to
`externalTrafficPolicy: Local`. In managed GCP, AWS, or Azure mode it instead installs
the pinned upstream Traefik Helm chart, schedules replicas on the managed
application nodes, and binds its external Service to the static address
reserved by Terraform. AWS first installs the pinned AWS Load Balancer
Controller and uses EKS Pod Identity for its IAM permissions. Its public NLB
uses Terraform's Elastic IP, while a second internal NLB uses the configured
private ingress address for the Tailscale-only Headlamp, Homepage, and
Technitium hostnames. AKS uses Azure Load Balancer annotations to bind the
Terraform-managed public IP and a second internal load balancer to the private
ingress address.

In self-managed mode, the GCP external ingress load balancer and private
Technitium records both target the agent nodes. In managed GCP, AWS, and Azure,
separate public and internal Services target the same Traefik pods. Keeping local endpoints
lets Kubernetes preserve the source address needed by the private-service IP
allow-lists.

The role is the first stage of `oilscope.platform.deploy_k3s_addons` and waits
for the Service, and in self-managed mode the K3s Helm controller, to finish
reconciling before the other add-ons continue.
