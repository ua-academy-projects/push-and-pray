#!/usr/bin/env python3
"""Validate external project configuration and initialize the GCS backend."""

from __future__ import annotations

import argparse
import json
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
TERRAFORM_ROOT = REPOSITORY_ROOT / "infrastructure" / "terraform"
DEFAULT_CONFIG = TERRAFORM_ROOT / "config" / "dev.json"
DEFAULT_SCHEMA = TERRAFORM_ROOT / "project-config.schema.json"

BACKEND_KEYS = frozenset({"bucket", "prefix"})
BUCKET_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$")
PREFIX_PATTERN = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9._/-]*[A-Za-z0-9])?$")


class PreflightError(ValueError):
    """Raised when configuration is unsafe or invalid for backend initialization."""


def load_json(path: Path, description: str) -> Any:
    try:
        with path.open(encoding="utf-8") as stream:
            return json.load(stream)
    except FileNotFoundError as error:
        raise PreflightError(f"{description} does not exist: {path}") from error
    except json.JSONDecodeError as error:
        raise PreflightError(
            f"{description} is not valid JSON at line {error.lineno}, column {error.colno}: "
            f"{error.msg}"
        ) from error


def validate_project_config(config_path: Path, schema_path: Path) -> dict[str, Any]:
    config = load_json(config_path, "Project configuration")
    schema = load_json(schema_path, "Project configuration schema")

    Draft202012Validator.check_schema(schema)
    errors = sorted(
        Draft202012Validator(schema).iter_errors(config),
        key=lambda error: tuple(str(part) for part in error.absolute_path),
    )
    if errors:
        error = errors[0]
        location = ".".join(str(part) for part in error.absolute_path) or "<root>"
        raise PreflightError(
            f"Project configuration failed JSON Schema at {location}: {error.message}"
        )

    if not isinstance(config, dict):
        raise PreflightError("Project configuration root must be a JSON object.")
    return config


def read_backend_settings(config: dict[str, Any]) -> tuple[str, str]:
    terraform_config = config.get("terraform")
    if not isinstance(terraform_config, dict):
        raise PreflightError("terraform must be a JSON object.")

    backend = terraform_config.get("backend")
    if not isinstance(backend, dict):
        raise PreflightError("terraform.backend must be a JSON object.")

    actual_keys = frozenset(backend)
    if actual_keys != BACKEND_KEYS:
        unexpected = sorted(actual_keys - BACKEND_KEYS)
        missing = sorted(BACKEND_KEYS - actual_keys)
        details = []
        if unexpected:
            details.append(f"unexpected fields: {', '.join(unexpected)}")
        if missing:
            details.append(f"missing fields: {', '.join(missing)}")
        raise PreflightError(
            "terraform.backend accepts exactly bucket and prefix; " + "; ".join(details)
        )

    bucket = backend["bucket"]
    prefix = backend["prefix"]
    if not isinstance(bucket, str) or not BUCKET_PATTERN.fullmatch(bucket):
        raise PreflightError("terraform.backend.bucket is not a valid GCS bucket name.")
    if not isinstance(prefix, str) or len(prefix) > 512 or not PREFIX_PATTERN.fullmatch(prefix):
        raise PreflightError("terraform.backend.prefix is not a valid non-empty state prefix.")

    return bucket, prefix


def validate_terraform_arguments(arguments: list[str]) -> None:
    forbidden = [
        argument
        for argument in arguments
        if argument == "-backend=false"
        or argument == "-chdir"
        or argument.startswith("-chdir=")
        or argument == "-backend-config"
        or argument.startswith("-backend-config=")
    ]
    if forbidden:
        raise PreflightError(
            "Backend coordinates and Terraform directory are controlled by preflight; "
            f"remove forbidden arguments: {', '.join(forbidden)}"
        )

    if "-migrate-state" in arguments and "-reconfigure" in arguments:
        raise PreflightError("-migrate-state and -reconfigure cannot be used together.")


def build_init_command(
    terraform_root: Path,
    bucket: str,
    prefix: str,
    terraform_arguments: list[str],
) -> list[str]:
    validate_terraform_arguments(terraform_arguments)
    return [
        "terraform",
        f"-chdir={terraform_root}",
        "init",
        *terraform_arguments,
        f"-backend-config=bucket={bucket}",
        f"-backend-config=prefix={prefix}",
    ]


def parse_arguments() -> tuple[argparse.Namespace, list[str]]:
    parser = argparse.ArgumentParser(
        description=(
            "Validate external project JSON and initialize Terraform with only its approved "
            "GCS backend bucket and prefix."
        )
    )
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    parser.add_argument("--terraform-dir", type=Path, default=TERRAFORM_ROOT)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate and print the non-secret Terraform command without executing it.",
    )
    parsed, terraform_arguments = parser.parse_known_args()
    if terraform_arguments[:1] == ["--"]:
        terraform_arguments = terraform_arguments[1:]
    return parsed, terraform_arguments


def main() -> int:
    arguments, terraform_arguments = parse_arguments()
    try:
        config = validate_project_config(arguments.config.resolve(), arguments.schema.resolve())
        bucket, prefix = read_backend_settings(config)
        command = build_init_command(
            arguments.terraform_dir.resolve(), bucket, prefix, terraform_arguments
        )
        if not arguments.terraform_dir.is_dir():
            raise PreflightError(f"Terraform directory does not exist: {arguments.terraform_dir}")
        if shutil.which("terraform") is None and not arguments.dry_run:
            raise PreflightError("terraform executable was not found on PATH.")
    except (PreflightError, TypeError, ValueError) as error:
        print(f"Preflight failed: {error}", file=sys.stderr)
        return 2

    print(f"Preflight passed for {arguments.config.resolve()}")
    print(f"Backend bucket: {bucket}")
    print(f"State prefix: {prefix}")
    if arguments.dry_run:
        print(f"Command: {shlex.join(command)}")
        return 0

    # The executable and backend arguments are constructed above and shell expansion is disabled.
    return subprocess.run(command, check=False).returncode  # noqa: S603


if __name__ == "__main__":
    raise SystemExit(main())
