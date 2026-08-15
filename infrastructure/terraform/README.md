# Terraform Infrastructure

Terraform configuration for the GCP deployment of the Oil Price Tracker.

## Structure

- `modules/network` - VPC, subnet, routing, NAT, and firewall resources.
- `modules/bastion` - bastion host and SSH access resources.
- `modules/compute` - application VM resources.

## Requirements

- Terraform 1.15.x
- Google Cloud credentials through Application Default Credentials
- Access to the target GCP project

## Configuration

Create a local variable file:

```bash
cp terraform.tfvars.example terraform.tfvars
