#!/usr/bin/env python3
"""Render a secret-free Ansible inventory from the Terraform deployment contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--deployment", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def render_inventory(deployment: dict[str, Any]) -> dict[str, Any]:
    if deployment.get("contract_version") != 1:
        raise ValueError("Unsupported deployment contract_version")

    nodes = deployment.get("nodes")
    bastion = deployment.get("bastion")
    if not isinstance(nodes, dict) or not nodes:
        raise ValueError("Deployment contract has no nodes")
    if not isinstance(bastion, dict) or not bastion.get("public_address"):
        raise ValueError("Deployment contract has no public bastion endpoint")

    bastion_name = bastion["logical_name"]
    bastion_user = bastion["ssh"]["user"]
    bastion_port = bastion["ssh"]["port"]
    bastion_host = bastion["public_address"]

    inventory: dict[str, Any] = {"all": {"hosts": {}, "children": {}}}
    groups: dict[str, list[str]] = {
        deployment["provider"]: [],
        "bastion": [],
        "workloads": [],
    }

    for logical_name, node in sorted(nodes.items()):
        role = node["role"]
        inventory_name = node.get("name") or logical_name
        is_bastion = role == "bastion"
        address = node.get("public_address") if is_bastion else node["private_address"]
        if not address:
            raise ValueError(f"Node {logical_name} has no reachable address")

        hostvars = {
            "ansible_host": address,
            "ansible_user": node["ssh"]["user"],
            "ansible_port": node["ssh"]["port"],
            "oilscope_cloud": node["provider"],
            "oilscope_role": role,
            "oilscope_vm_key": logical_name,
            "internal_ip": node["private_address"],
            "public_ip": node.get("public_address"),
            "runtime_identity": node["runtime_identity"],
        }
        if not is_bastion:
            hostvars["ansible_ssh_common_args"] = (
                f"-o IdentitiesOnly=yes -o ProxyJump={bastion_user}@{bastion_host}:{bastion_port}"
            )

        inventory["all"]["hosts"][inventory_name] = hostvars
        groups.setdefault(node["provider"], []).append(inventory_name)
        groups.setdefault(role, []).append(inventory_name)
        groups.setdefault(f"{node['provider']}_{role}", []).append(inventory_name)
        groups["bastion" if is_bastion else "workloads"].append(inventory_name)

    bastion_inventory_name = nodes[bastion_name].get("name") or bastion_name
    if bastion_inventory_name not in groups["bastion"]:
        raise ValueError("Bastion contract does not match a bastion node")

    for group, hosts in sorted(groups.items()):
        if not hosts:
            continue
        inventory[group] = {"hosts": {host: {} for host in sorted(set(hosts))}}
        inventory["all"]["children"][group] = {}
    return inventory


def main() -> None:
    args = parse_args()
    deployment = json.loads(args.deployment.read_text(encoding="utf-8"))
    inventory = render_inventory(deployment)
    args.output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(inventory, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    args.output.chmod(0o600)


if __name__ == "__main__":
    main()
