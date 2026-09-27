# Observability agent

Installs the cloud-native observability agent selected by inventory: Google
Cloud Ops Agent on GCP and Amazon CloudWatch Agent on AWS. Azure Monitor Agent
is installed by Terraform as a VM extension and connected to the deployment's
Data Collection Rule, so this Ansible role has no Azure installation step.

The role is selected from the neutral `oilscope_cloud` inventory variable. It
On AWS, the role uses the instance profile and requires the
`CloudWatchAgentServerPolicy` managed policy. Terraform attaches it to every
workload instance role; no AWS access keys are stored on a VM.
