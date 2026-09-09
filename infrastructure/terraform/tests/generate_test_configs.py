"""Generate deterministic, credential-free Terraform test configurations."""

import json
from copy import deepcopy
from pathlib import Path

TERRAFORM_ROOT = Path(__file__).resolve().parent.parent
REPOSITORY_ROOT = TERRAFORM_ROOT.parent.parent
OUTPUT_DIRECTORY = TERRAFORM_ROOT / ".terraform" / "test-configs"


def write_config(name: str, config: dict) -> None:
    destination = OUTPUT_DIRECTORY / f"{name}.json"
    destination.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    base = json.loads((REPOSITORY_ROOT / "project-config.example.json").read_text(encoding="utf-8"))
    OUTPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)

    aws_only = deepcopy(base)
    aws_only["default_cloud"] = "aws"
    aws_only["clouds"] = {"aws": {}}
    write_config("aws-only", aws_only)

    monitoring_absent = deepcopy(base)
    monitoring_absent.pop("monitoring")
    write_config("monitoring-absent", monitoring_absent)

    monitoring_disabled = deepcopy(base)
    monitoring_disabled["monitoring"]["enabled"] = False
    write_config("monitoring-disabled", monitoring_disabled)

    hybrid = deepcopy(base)
    hybrid["vms"]["ui"]["cloud"] = "aws"
    write_config("hybrid", hybrid)

    invalid_multi_region = deepcopy(base)
    invalid_multi_region["cloud_mappings"]["regions"]["secondary"] = deepcopy(
        invalid_multi_region["cloud_mappings"]["regions"][invalid_multi_region["default_region"]]
    )
    invalid_multi_region["cloud_mappings"]["regions"]["secondary"]["gcp"] = {
        "region": "us-central1",
        "zone": "us-central1-a",
    }
    invalid_multi_region["vms"]["history"]["region"] = "secondary"
    write_config("invalid-multi-region", invalid_multi_region)

    invalid_subnet = deepcopy(base)
    invalid_subnet["network"]["workload_subnet_cidr"] = invalid_subnet["network"][
        "management_subnet_cidr"
    ]
    write_config("invalid-subnet-overlap", invalid_subnet)

    role_duplicate = deepcopy(base)
    role_duplicate["vms"]["history"]["role"] = "fetcher"
    write_config("invalid-role-duplicate", role_duplicate)

    public_ip = deepcopy(base)
    public_ip["vms"]["ui"]["assign_public_ip"] = False
    write_config("invalid-public-ip", public_ip)

    reserved_label = deepcopy(base)
    reserved_label["common_labels"]["managed_by"] = "operator"
    write_config("invalid-reserved-label", reserved_label)

    undeclared = deepcopy(hybrid)
    undeclared["clouds"].pop("aws", None)
    write_config("invalid-provider-declaration", undeclared)

    region_override = deepcopy(base)
    region_override["cloud_mappings"]["regions"]["alias"] = deepcopy(
        base["cloud_mappings"]["regions"][base["default_region"]]
    )
    region_override["vms"]["history"]["region"] = "alias"
    write_config("region-override", region_override)


if __name__ == "__main__":
    main()
