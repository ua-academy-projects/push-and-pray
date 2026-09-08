# Inventory plugin

`inventory/oilscope_cloud.py` provides the
`oilscope.platform.oilscope_cloud` dynamic inventory plugin. It reads the
project configuration shared with Terraform and delegates live discovery to
the `amazon.aws.aws_ec2` and `google.cloud.gcp_compute` plugins.

The provider plugins run only when the configuration contains VMs for their
cloud. The wrapper normalizes discovered hosts, creates the `aws`, `gcp`, and
`workloads` groups, and creates functional groups from each VM's `tags`.

The inventory source and its connection variables remain outside the
collection under `infrastructure/ansible/inventory`. See the
[cloud inventory guide](../../../inventory/README.md) for installation,
authentication, and usage.
