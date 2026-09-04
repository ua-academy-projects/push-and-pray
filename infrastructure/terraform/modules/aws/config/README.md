# AWS configuration resolver

This nested module interprets the shared JSON contract for AWS. It selects AWS
VMs by `default_cloud` and per-VM override, applies profile defaults, resolves
the AWS catalog with `lookup`, normalizes metadata, and derives workload and
secret collections.

It creates no infrastructure and requires no provider.
