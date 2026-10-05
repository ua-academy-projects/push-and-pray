#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

set -a
source ../terraform.env
set +a

for vm in oilscope-dev-bastion oilscope-dev-infra oilscope-dev-fetcher; do
  if [[ "$(az vm show -g oilscope-dev-rg -n "$vm" -d --query powerState -o tsv)" != 'VM running' ]]; then
    az vm start -g oilscope-dev-rg -n "$vm" --output none
  fi
done

for vm in oilscope-dev-bastion-gcp oilscope-dev-ui; do
  if [[ "$(gcloud compute instances describe "$vm" --project=andrii-tf-2608261311 --zone=europe-central2-a --format='value(status)')" != RUNNING ]]; then
    gcloud compute instances start "$vm" --project=andrii-tf-2608261311 --zone=europe-central2-a --quiet
  fi
done

for id in i-0542a4632e80d3c74 i-04795c89c45c984d2; do
  if [[ "$(aws ec2 describe-instances --region eu-central-1 --instance-ids "$id" --query 'Reservations[0].Instances[0].State.Name' --output text)" != running ]]; then
    aws ec2 start-instances --region eu-central-1 --instance-ids "$id" --output json >/dev/null
  fi
done
aws ec2 wait instance-running --region eu-central-1 --instance-ids i-0542a4632e80d3c74 i-04795c89c45c984d2
