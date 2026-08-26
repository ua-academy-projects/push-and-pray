import copy
import json
import sys
from pathlib import Path
from typing import Any

import pytest
from scripts.validate_project_config import (
    load_json,
    main,
    validate_location_semantics,
    validate_network_semantics,
    validate_public_ip_policy,
    validate_role_and_tag_semantics,
    validate_schema,
    validate_semantics,
)

PROJECT_ROOT = Path(__file__).resolve().parents[2]
EXAMPLE_PATH = PROJECT_ROOT / "project-config.example.json"
SCHEMA_PATH = PROJECT_ROOT / "infrastructure" / "terraform" / "project-config.schema.json"


@pytest.fixture
def config() -> dict[str, Any]:
    return load_json(EXAMPLE_PATH)


@pytest.fixture
def schema() -> dict[str, Any]:
    return load_json(SCHEMA_PATH)


def test_example_passes_schema_and_semantic_validation(
    config: dict[str, Any],
    schema: dict[str, Any],
) -> None:
    assert validate_schema(config, schema) == []
    assert validate_semantics(config) == []


def test_schema_reports_missing_required_property(
    config: dict[str, Any],
    schema: dict[str, Any],
) -> None:
    del config["project_id"]

    errors = validate_schema(config, schema)

    assert any("'project_id' is a required property" in error for error in errors)


def test_schema_rejects_registry_repository_with_whitespace(
    config: dict[str, Any],
    schema: dict[str, Any],
) -> None:
    config["registry"]["repository"] = "ghcr.io/example org/project"

    errors = validate_schema(config, schema)

    assert any("registry.repository" in error for error in errors)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("management_subnet_cidr", "10.0.0.1/29"),
        ("workload_subnet_cidr", "2001:db8::/64"),
    ],
)
def test_network_rejects_invalid_subnet_cidr(
    config: dict[str, Any],
    field: str,
    value: str,
) -> None:
    config["network"][field] = value

    assert validate_network_semantics(config)


def test_network_rejects_overlapping_subnets(config: dict[str, Any]) -> None:
    config["network"]["workload_subnet_cidr"] = "10.0.0.0/28"

    errors = validate_network_semantics(config)

    assert any("must not overlap" in error for error in errors)


def test_network_rejects_ip_outside_expected_subnet(config: dict[str, Any]) -> None:
    config["vms"]["history"]["internal_ip"] = "10.0.2.3"

    errors = validate_network_semantics(config)

    assert any("vms.history.internal_ip" in error and "outside" in error for error in errors)


def test_network_rejects_duplicate_internal_ip(config: dict[str, Any]) -> None:
    config["vms"]["fetcher"]["internal_ip"] = config["vms"]["history"]["internal_ip"]

    errors = validate_network_semantics(config)

    assert any("duplicates vms.history.internal_ip" in error for error in errors)


def test_network_rejects_gcp_reserved_internal_ip(config: dict[str, Any]) -> None:
    config["vms"]["history"]["internal_ip"] = "10.0.1.1"

    errors = validate_network_semantics(config)

    assert any(
        "vms.history.internal_ip" in error and "reserved by GCP" in error for error in errors
    )


def test_network_rejects_invalid_allowed_cidr(config: dict[str, Any]) -> None:
    config["vms"]["bastion"]["allowed_cidrs"] = ["192.0.2.10/24"]

    errors = validate_network_semantics(config)

    assert any("vms.bastion.allowed_cidrs.0" in error for error in errors)


@pytest.mark.parametrize(
    ("region", "zone"),
    [
        ("EUROPE-WEST1", "europe-west1-b"),
        ("europe-west1", "europe-west1"),
        ("europe-west1", "us-east1-b"),
    ],
)
def test_location_rejects_invalid_or_mismatched_values(
    config: dict[str, Any],
    region: str,
    zone: str,
) -> None:
    config["region"] = region
    config["zone"] = zone

    assert validate_location_semantics(config)


def test_roles_reject_additional_bastion(config: dict[str, Any]) -> None:
    duplicate_bastion = copy.deepcopy(config["vms"]["bastion"])
    duplicate_bastion["internal_ip"] = "10.0.0.3"
    config["vms"]["second-bastion"] = duplicate_bastion

    errors = validate_role_and_tag_semantics(config)

    assert any("exactly one bastion" in error for error in errors)


def test_tags_reject_cross_role_firewall_access(config: dict[str, Any]) -> None:
    config["vms"]["ui"]["network_tags"] = ["ui", "infra"]

    errors = validate_role_and_tag_semantics(config)

    assert any("vms.ui.network_tags" in error for error in errors)


def test_public_ip_rejected_for_private_workload(config: dict[str, Any]) -> None:
    config["vms"]["history"]["assign_public_ip"] = True

    errors = validate_public_ip_policy(config)

    assert any("vms.history.assign_public_ip" in error for error in errors)


def test_public_ip_required_for_bastion(config: dict[str, Any]) -> None:
    config["vms"]["bastion"]["assign_public_ip"] = False

    errors = validate_public_ip_policy(config)

    assert any("vms.bastion.assign_public_ip" in error for error in errors)


def test_load_json_rejects_invalid_json(tmp_path: Path) -> None:
    invalid_json = tmp_path / "invalid.json"
    invalid_json.write_text("{invalid", encoding="utf-8")

    with pytest.raises(json.JSONDecodeError):
        load_json(invalid_json)


def test_cli_returns_failure_for_semantic_error(
    config: dict[str, Any],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    config["vms"]["ui"]["network_tags"] = ["ui", "infra"]
    config_path = tmp_path / "invalid-project-config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    monkeypatch.setattr(sys, "argv", ["validate_project_config.py", str(config_path)])

    assert main() == 1
    assert "vms.ui.network_tags" in capsys.readouterr().err
