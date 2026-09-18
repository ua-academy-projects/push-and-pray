#!/usr/bin/env python3
"""Validate cross-field contracts that JSON Schema cannot express."""

from __future__ import annotations

import argparse
import ipaddress
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any


class ConfigError(ValueError):
    """A project configuration violates a deployment contract."""


def _network_for(config: dict[str, Any], provider: str) -> dict[str, Any]:
    return config["network"] | config.get("clouds", {}).get(provider, {}).get(
        "network", {}
    )


def _provider_for(config: dict[str, Any], vm: dict[str, Any]) -> str:
    return str(
        vm.get(
            "provider",
            vm.get("cloud", config.get("cloud_provider", config.get("default_cloud", ""))),
        )
    ).lower()


def _vm_subnet_key(provider: str, vm: dict[str, Any]) -> str:
    if vm["role"] == "bastion":
        return "management_subnet_cidr"
    if provider == "aws" and vm["assign_public_ip"]:
        return "public_subnet_cidr"
    return "workload_subnet_cidr"


def _reserved_addresses(
    provider: str, subnet: ipaddress.IPv4Network
) -> set[ipaddress.IPv4Address]:
    if provider == "aws":
        offsets = (0, 1, 2, 3, subnet.num_addresses - 1)
    else:
        offsets = (0, 1, subnet.num_addresses - 2, subnet.num_addresses - 1)
    return {subnet.network_address + offset for offset in offsets}


def _looks_like_secret_value(value: str) -> bool:
    """Reject common credential shapes without logging the candidate value."""
    return bool(
        re.fullmatch(r"[0-9a-fA-F]{32,}", value)
        or re.match(r"^(?:sk-|ghp_|github_pat_|AKIA|ASIA|AIza)", value)
        or "PRIVATE KEY-----" in value
        or "\n" in value
    )


def validate_config(config: dict[str, Any]) -> None:
    schema_version = int(config.get("schema_version", 0))
    global_provider = str(
        config.get("cloud_provider", config.get("default_cloud", ""))
    ).lower()
    if global_provider not in {"aws", "gcp"}:
        raise ConfigError("cloud_provider/default_cloud must be aws or gcp")
    if schema_version > 0 and config.get("cloud_provider") != global_provider:
        raise ConfigError("versioned configs must define cloud_provider")
    if config.get("deployment_runtime", "compose").lower() != "compose":
        raise ConfigError("only deployment_runtime=compose is implemented")

    data_profile = config.get(
        "data_profile", "managed" if config.get("manage_db", False) else "portable"
    ).lower()
    if data_profile not in {"managed", "portable"}:
        raise ConfigError("data_profile must be managed or portable")

    for role, mappings in config.get("secrets_by_role", {}).items():
        if not isinstance(mappings, dict):
            raise ConfigError(f"secrets_by_role.{role} must be an object")
        for environment_name, reference in mappings.items():
            if not isinstance(reference, str) or not reference.strip():
                raise ConfigError(
                    f"secrets_by_role.{role}.{environment_name} must be a secret reference"
                )
            if _looks_like_secret_value(reference):
                raise ConfigError(
                    f"secrets_by_role.{role}.{environment_name} looks like a secret value; "
                    "store only its provider secret reference"
                )

    image_sha = str(config.get("registry", {}).get("image_sha", ""))
    if not re.fullmatch(r"[0-9a-f]{40}", image_sha):
        raise ConfigError("registry.image_sha must be a full lowercase Git commit SHA")
    if data_profile == "managed":
        for service in ("redis", "rabbitmq"):
            image = str(config.get("managed_services", {}).get(service, {}).get("source_image", ""))
            if not re.fullmatch(r"[^\s@]+@sha256:[0-9a-f]{64}", image):
                raise ConfigError(
                    f"managed_services.{service}.source_image must include an exact sha256 digest"
                )

    vms = config.get("vms", {})
    if not vms:
        raise ConfigError("at least one VM must be defined")
    roles = Counter(vm["role"] for vm in vms.values())
    required_roles = {"bastion", "history", "fetcher", "ui"}
    if data_profile == "portable":
        required_roles.add("database")
    for role in sorted(required_roles):
        if roles[role] != 1:
            raise ConfigError(f"exactly one VM with role {role} is required")
    if data_profile == "managed":
        if roles["database"]:
            raise ConfigError("managed profile must not define a database VM")
        database = config.get("database")
        if not isinstance(database, dict):
            raise ConfigError("managed profile must define database settings")
        if str(database.get("cloud", global_provider)).lower() != global_provider:
            raise ConfigError("managed database provider must match cloud_provider")
        if database.get("publicly_accessible") is True or database.get("public_ip") is True:
            raise ConfigError("managed database must not be publicly accessible")
    elif config.get("database") is not None:
        raise ConfigError("portable profile must not define managed database settings")

    providers = {_provider_for(config, vm) for vm in vms.values()}
    if not providers <= {"aws", "gcp"}:
        raise ConfigError("each VM provider must be aws or gcp")
    if schema_version > 0 and providers != {global_provider}:
        raise ConfigError("versioned configs cannot mix VM providers")

    networks: dict[str, dict[str, Any]] = {
        provider: _network_for(config, provider) for provider in providers
    }
    parsed_networks: dict[str, dict[str, ipaddress.IPv4Network]] = {}
    for provider, network in networks.items():
        try:
            parsed = {
                key: ipaddress.ip_network(value, strict=True)
                for key, value in network.items()
                if key.endswith("_cidr")
            }
            database_subnets = [
                ipaddress.ip_network(value, strict=True)
                for value in network.get("database_subnet_cidrs", [])
            ]
        except ValueError as error:
            raise ConfigError(f"invalid {provider} network CIDR: {error}") from error
        required = {
            "vpc_cidr",
            "management_subnet_cidr",
            "workload_subnet_cidr",
            "public_subnet_cidr",
        }
        missing = required - parsed.keys()
        if missing:
            raise ConfigError(f"{provider} network is missing: {', '.join(sorted(missing))}")
        if not all(isinstance(item, ipaddress.IPv4Network) for item in parsed.values()):
            raise ConfigError(f"{provider} deployment supports IPv4 networks only")
        vpc = parsed["vpc_cidr"]
        subnet_keys = {
            "management_subnet_cidr",
            "workload_subnet_cidr",
            "public_subnet_cidr",
        }
        children = [(key, parsed[key]) for key in sorted(subnet_keys)]
        children.extend(
            (f"database_subnet_cidrs[{index}]", subnet)
            for index, subnet in enumerate(database_subnets)
        )
        for name, subnet in children:
            if not subnet.subnet_of(vpc):
                raise ConfigError(f"{provider} {name}={subnet} must be inside {vpc}")
        non_overlapping_ranges = list(children)
        if "database_private_service_cidr" in parsed:
            non_overlapping_ranges.append(
                (
                    "database_private_service_cidr",
                    parsed["database_private_service_cidr"],
                )
            )
        for index, (left_name, left) in enumerate(non_overlapping_ranges):
            for right_name, right in non_overlapping_ranges[index + 1 :]:
                if left.overlaps(right):
                    raise ConfigError(
                        f"{provider} network ranges overlap: "
                        f"{left_name}={left} and {right_name}={right}"
                    )
        parsed_networks[provider] = parsed

    addresses: set[tuple[str, ipaddress.IPv4Address]] = set()
    public_roles: Counter[str] = Counter()
    bastions: Counter[str] = Counter()
    for name, vm in vms.items():
        provider = _provider_for(config, vm)
        if vm["role"] == "bastion":
            bastions[provider] += 1
        if vm["assign_public_ip"]:
            public_roles[vm["role"]] += 1
            if vm["role"] not in {"bastion", "ui"}:
                raise ConfigError(f"VM {name} role {vm['role']} cannot have a public IP")
        subnet_key = _vm_subnet_key(provider, vm)
        subnet = parsed_networks[provider][subnet_key]
        try:
            address = ipaddress.ip_address(vm["internal_ip"])
        except ValueError as error:
            raise ConfigError(f"VM {name} has invalid internal_ip: {error}") from error
        if not isinstance(address, ipaddress.IPv4Address):
            raise ConfigError(f"VM {name} internal_ip must be IPv4")
        if address not in subnet:
            raise ConfigError(
                f"VM {name} internal_ip {address} must be inside "
                f"{subnet_key} ({subnet})"
            )
        if address in _reserved_addresses(provider, subnet):
            raise ConfigError(
                f"VM {name} internal_ip {address} is reserved by {provider} in {subnet}"
            )
        address_key = (provider, address)
        if address_key in addresses:
            raise ConfigError(f"duplicate {provider} internal_ip: {address}")
        addresses.add(address_key)

    if public_roles["ui"] != 1:
        raise ConfigError("exactly one public UI VM is required")
    for provider in providers:
        if bastions[provider] != 1:
            raise ConfigError(f"exactly one bastion is required for {provider}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    args = parser.parse_args()
    try:
        with args.config.open(encoding="utf-8") as config_file:
            config = json.load(config_file)
        validate_config(config)
    except (OSError, json.JSONDecodeError, ConfigError, KeyError, TypeError) as error:
        parser.exit(1, f"ERROR: {error}\n")
    print(f"Project config contracts valid: {args.config}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
