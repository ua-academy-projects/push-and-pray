# Multi-cloud dynamic inventory

oilscope.yml uses oilscope.platform.oilscope_cloud. The wrapper reads the same
JSON as Terraform and delegates discovery to GCP and/or AWS based on
default_cloud plus every vms.*.cloud override.

Providers are filtered by application, environment and cloud metadata. Role
metadata creates bastion, database, history, fetcher, ui and workloads groups.
Provider groups include gcp, aws, gcp_bastion and aws_bastion.

## Setup

    pip install -r infrastructure/ansible/requirements.txt
    ansible-galaxy collection install -r infrastructure/ansible/requirements.yml

Build and install the local oilscope.platform collection after every plugin or
role change.

## Usage

    export OILSCOPE_PROJECT_CONFIG=/absolute/path/project-config.json
    ansible-inventory -i infrastructure/ansible/inventory/oilscope.yml --graph

An empty inventory before terraform apply is valid. Verify an unexpected empty
result directly with gcloud compute instances list or
aws ec2 describe-instances.

Every host gets internal_ip, public_ip, oilscope_role, oilscope_cloud,
oilscope_vm_key, ansible_host and ansible_port. Workloads select the bastion
group belonging to their own cloud; no cross-cloud SSH routing is created.

For a new bastion, enable Terraform's temporary port-22 rule, set
OILSCOPE_BASTION_CONNECT_PORT=22, run the bastion playbook, unset the variable,
then apply Terraform again without the bootstrap flag.
