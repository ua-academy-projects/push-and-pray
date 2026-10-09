# Managed Kubernetes kubeconfig role

Runs on the local Ansible controller after Terraform creates GKE, EKS, or AKS.
It reads the selected cloud from `project-config.json` and uses that provider's
authenticated CLI to write `~/.kube/oilscope-<environment>.yaml`. This is the
same path consumed by the existing Kubernetes add-on, migration, secret, and
application roles.

GKE credentials are requested with the configured region because the managed
GCP implementation is a regional cluster. EKS and AKS use their configured
region and resource group respectively.

The generated kubeconfig uses the provider CLI's normal exec-based credentials;
no cloud credential or Kubernetes token is committed to the repository. The
role sets mode `0600` and verifies access by listing cluster nodes.

Run it from the repository root:

```bash
ansible-playbook oilscope.platform.configure_managed_kubernetes \
  -i localhost,
```
