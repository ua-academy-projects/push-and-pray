# Amazon CloudWatch Agent role

Installs the Amazon CloudWatch Agent on Ubuntu EC2 instances, writes a local
configuration, and ensures the systemd service is enabled and running. The
configuration sends CPU, memory, root filesystem, and swap metrics to the
`CWAgent` namespace.

The EC2 instance profile must have the AWS-managed
`CloudWatchAgentServerPolicy`. Terraform attaches it in the `iam` module.
