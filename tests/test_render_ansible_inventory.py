from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.render_ansible_inventory import render_inventory  # noqa: E402


def _node(role: str, private: str, public: str | None = None) -> dict:
    return {
        "role": role,
        "provider": "aws",
        "private_address": private,
        "public_address": public,
        "runtime_identity": f"identity/{role}",
        "ssh": {"user": "ubuntu", "port": 8787 if role == "bastion" else 22},
    }


def test_inventory_uses_public_bastion_and_private_workload_addresses() -> None:
    bastion = {"logical_name": "bastion"} | _node("bastion", "10.0.0.10", "198.51.100.10")
    deployment = {
        "contract_version": 1,
        "provider": "aws",
        "bastion": bastion,
        "nodes": {
            "bastion": bastion,
            "history": _node("history", "10.0.1.10"),
            "ui": _node("ui", "10.0.1.11", "198.51.100.11"),
        },
    }

    inventory = render_inventory(deployment)

    assert inventory["all"]["hosts"]["bastion"]["ansible_host"] == "198.51.100.10"
    assert inventory["all"]["hosts"]["bastion"]["bastion_ssh_port"] == 8787
    assert "StrictHostKeyChecking=accept-new" in inventory["all"]["hosts"]["bastion"][
        "ansible_ssh_common_args"
    ]
    history = inventory["all"]["hosts"]["history"]
    assert history["ansible_host"] == "10.0.1.10"
    assert history["oilscope_vm_key"] == "history"
    assert "ProxyJump=ubuntu@198.51.100.10:8787" in history["ansible_ssh_common_args"]
    assert list(inventory["history"]["hosts"]) == ["history"]
    assert sorted(inventory["workloads"]["hosts"]) == ["history", "ui"]
    assert list(inventory["aws_bastion"]["hosts"]) == ["bastion"]


def test_inventory_contains_no_secret_fields() -> None:
    bastion = {"logical_name": "bastion"} | _node("bastion", "10.0.0.10", "198.51.100.10")
    inventory = render_inventory(
        {
            "contract_version": 1,
            "provider": "aws",
            "bastion": bastion,
            "nodes": {"bastion": bastion},
        }
    )

    rendered = str(inventory).lower()
    assert "password" not in rendered
    assert "private_key" not in rendered
    assert "token" not in rendered
