# Observability agent

Installs the cloud-native observability agent selected by inventory: Google
Cloud Ops Agent on GCP and Amazon CloudWatch Agent on AWS. Both agents collect
host metrics and Docker JSON logs under `/var/lib/docker/containers`.

The role is selected from the neutral `oilscope_cloud` inventory variable. It
On AWS, the role uses the instance profile and requires the
`CloudWatchAgentServerPolicy` managed policy. Terraform attaches it to every
workload instance role; no AWS access keys are stored on a VM.
