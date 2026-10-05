#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

set -a
source ../terraform.env
set +a

for vm in oilscope-dev-fetcher oilscope-dev-infra oilscope-dev-bastion; do
  if [[ "$(az vm show -g oilscope-dev-rg -n "$vm" -d --query powerState -o tsv)" != 'VM deallocated' ]]; then
    az vm deallocate -g oilscope-dev-rg -n "$vm" --output none
  fi
done

for vm in oilscope-dev-ui oilscope-dev-bastion-gcp; do
  if [[ "$(gcloud compute instances describe "$vm" --project=andrii-tf-2608261311 --zone=europe-central2-a --format='value(status)')" != TERMINATED ]]; then
    gcloud compute instances stop "$vm" --project=andrii-tf-2608261311 --zone=europe-central2-a --quiet
  fi
done

for id in i-04795c89c45c984d2 i-0542a4632e80d3c74; do
  if [[ "$(aws ec2 describe-instances --region eu-central-1 --instance-ids "$id" --query 'Reservations[0].Instances[0].State.Name' --output text)" != stopped ]]; then
    aws ec2 stop-instances --region eu-central-1 --instance-ids "$id" --output json >/dev/null
  fi
done
aws ec2 wait instance-stopped --region eu-central-1 --instance-ids i-04795c89c45c984d2 i-0542a4632e80d3c74
