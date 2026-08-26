import argparse
import json
import re
import sys
from ipaddress import IPv4Address, IPv4Network, ip_address, ip_network
from json import JSONDecodeError
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator
from jsonschema.exceptions import SchemaError, ValidationError

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SCHEMA_PATH = PROJECT_ROOT / "infrastructure" / "terraform" / "project-config.schema.json"
REGION_PATTERN = re.compile(r"^[a-z]+(?:-[a-z]+)+[0-9]+$")
ZONE_PATTERN = re.compile(r"^[a-z]+(?:-[a-z]+)+[0-9]+-[a-z]$")
NETWORK_TAG_BY_ROLE = {
    "bastion": "bastion",
    "database": "infra",
    "history": "history",
    "fetcher": "fetcher",
    "ui": "ui",
}
PUBLIC_IP_ROLES = {"bastion", "ui"}


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def format_error_path(error: ValidationError) -> str:
    parts = [str(part) for part in error.absolute_path]
    return ".".join(parts) if parts else "<root>"


def validate_schema(config: Any, schema: Any) -> list[str]:
    Draft202012Validator.check_schema(schema)

    validator = Draft202012Validator(schema)
    errors = sorted(
        validator.iter_errors(config),
        key=lambda error: tuple(str(part) for part in error.absolute_path),
    )

    return [f"{format_error_path(error)}: {error.message}" for error in errors]


def parse_ipv4_network(
    value: str,
    path: str,
    errors: list[str],
) -> IPv4Network | None:
    try:
        network = ip_network(value, strict=True)
    except ValueError:
        errors.append(f"{path}: must be a canonical IPv4 CIDR.")
        return None

    if not isinstance(network, IPv4Network):
        errors.append(f"{path}: must be an IPv4 CIDR.")
        return None

    return network


def parse_ipv4_address(
    value: str,
    path: str,
    errors: list[str],
) -> IPv4Address | None:
    try:
        address = ip_address(value)
    except ValueError:
        errors.append(f"{path}: must be a valid IPv4 address.")
        return None

    if not isinstance(address, IPv4Address):
        errors.append(f"{path}: must be an IPv4 address.")
        return None

    return address


def validate_network_semantics(config: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    network_config = config["network"]

    management_subnet = parse_ipv4_network(
        network_config["management_subnet_cidr"],
        "network.management_subnet_cidr",
        errors,
    )
    workload_subnet = parse_ipv4_network(
        network_config["workload_subnet_cidr"],
        "network.workload_subnet_cidr",
        errors,
    )

    subnets = {
        "network.management_subnet_cidr": management_subnet,
        "network.workload_subnet_cidr": workload_subnet,
    }

    for path, subnet in subnets.items():
        if subnet is not None and not 4 <= subnet.prefixlen <= 29:
            errors.append(f"{path}: prefix length must be between /4 and /29 for a GCP subnet.")

    if (
        management_subnet is not None
        and workload_subnet is not None
        and management_subnet.overlaps(workload_subnet)
    ):
        errors.append("network: management and workload subnet CIDRs must not overlap.")

    seen_addresses: dict[IPv4Address, str] = {}

    for vm_name, vm in config["vms"].items():
        address_path = f"vms.{vm_name}.internal_ip"
        address = parse_ipv4_address(
            vm["internal_ip"],
            address_path,
            errors,
        )

        for index, allowed_cidr in enumerate(vm.get("allowed_cidrs", [])):
            parse_ipv4_network(
                allowed_cidr,
                f"vms.{vm_name}.allowed_cidrs.{index}",
                errors,
            )

        if address is None:
            continue

        previous_vm = seen_addresses.get(address)

        if previous_vm is not None:
            errors.append(f"{address_path}: duplicates vms.{previous_vm}.internal_ip.")
        else:
            seen_addresses[address] = vm_name

        if vm["role"] == "bastion":
            expected_subnet = management_subnet
            expected_subnet_name = "management"
        else:
            expected_subnet = workload_subnet
            expected_subnet_name = "workload"

        if expected_subnet is None:
            continue

        if address not in expected_subnet:
            errors.append(
                f"{address_path}: {address} is outside the "
                f"{expected_subnet_name} subnet {expected_subnet}."
            )
            continue

        reserved_addresses = {
            expected_subnet.network_address,
            expected_subnet.network_address + 1,
            expected_subnet.broadcast_address - 1,
            expected_subnet.broadcast_address,
        }

        if address in reserved_addresses:
            errors.append(
                f"{address_path}: {address} is reserved by GCP within subnet {expected_subnet}."
            )

    return errors


def validate_location_semantics(config: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    region = config["region"]
    zone = config["zone"]

    if REGION_PATTERN.fullmatch(region) is None:
        errors.append("region: must use a standard GCP region format, for example europe-west1.")

    if ZONE_PATTERN.fullmatch(zone) is None:
        errors.append("zone: must use a standard GCP zone format, for example europe-west1-b.")
    elif zone.rsplit("-", maxsplit=1)[0] != region:
        errors.append(f"zone: {zone} does not belong to configured region {region}.")

    return errors


def validate_role_and_tag_semantics(config: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    vms = config["vms"]

    bastion_vms = [vm_name for vm_name, vm in vms.items() if vm["role"] == "bastion"]

    if bastion_vms != ["bastion"]:
        errors.append(
            "vms: exactly one bastion role is required, and it must be assigned to vms.bastion."
        )

    for vm_name, vm in vms.items():
        role = vm["role"]
        expected_tag = NETWORK_TAG_BY_ROLE[role]

        if vm["network_tags"] != [expected_tag]:
            errors.append(
                f"vms.{vm_name}.network_tags: role {role!r} "
                f"must have exactly the {expected_tag!r} tag."
            )

    return errors


def validate_public_ip_policy(config: dict[str, Any]) -> list[str]:
    errors: list[str] = []

    for vm_name, vm in config["vms"].items():
        role = vm["role"]
        assign_public_ip = vm["assign_public_ip"]

        if assign_public_ip and role not in PUBLIC_IP_ROLES:
            errors.append(
                f"vms.{vm_name}.assign_public_ip: public IPs are allowed "
                "only for bastion and ui roles."
            )

        if role == "bastion" and not assign_public_ip:
            errors.append(f"vms.{vm_name}.assign_public_ip: the bastion must have a public IP.")

    return errors


def validate_semantics(config: dict[str, Any]) -> list[str]:
    errors = validate_network_semantics(config)
    errors.extend(validate_location_semantics(config))
    errors.extend(validate_role_and_tag_semantics(config))
    errors.extend(validate_public_ip_policy(config))
    return errors


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate a project configuration against its JSON Schema."
    )
    parser.add_argument(
        "config",
        type=Path,
        help="Path to the project configuration JSON file.",
    )
    parser.add_argument(
        "--schema",
        type=Path,
        default=DEFAULT_SCHEMA_PATH,
        help=f"Path to the JSON Schema. Default: {DEFAULT_SCHEMA_PATH}",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_arguments()

    try:
        config = load_json(args.config)
        schema = load_json(args.schema)
        errors = validate_schema(config, schema)

        if not errors:
            errors = validate_semantics(config)
    except JSONDecodeError as error:
        print(f"Invalid JSON syntax: {error}", file=sys.stderr)
        return 1
    except OSError as error:
        print(f"Cannot read configuration file: {error}", file=sys.stderr)
        return 1
    except SchemaError as error:
        print(f"Invalid JSON Schema: {error.message}", file=sys.stderr)
        return 1

    if errors:
        print("Project configuration validation failed:", file=sys.stderr)

        for error in errors:
            print(f"- {error}", file=sys.stderr)

        return 1

    print(f"Project configuration is valid: {args.config}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
