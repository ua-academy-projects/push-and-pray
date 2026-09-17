from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
SCRIPT = REPOSITORY / "scripts" / "bootstrap-cloud.sh"
AWS_CONFIG = REPOSITORY / "configs" / "project-config.aws.json"
GCP_CONFIG = REPOSITORY / "configs" / "project-config.gcp.json"


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def _aws_environment(tmp_path: Path) -> tuple[dict[str, str], Path]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    calls = tmp_path / "aws-calls.log"
    _write_executable(
        bin_dir / "aws",
        """#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "${FAKE_AWS_CALLS}"
case "$1 $2" in
  "sts get-caller-identity")
    printf '%s\\n' \
      '{"Account":"123456789012",'\
      '"Arn":"arn:aws:iam::123456789012:user/test","UserId":"test"}'
    ;;
  "iam list-open-id-connect-providers")
    printf '%s\\n' '{"OpenIDConnectProviderList":[]}'
    ;;
  "s3api head-bucket"|"iam get-role")
    exit 255
    ;;
  *)
    printf '%s\\n' '{}'
    ;;
esac
""",
    )
    environment = os.environ.copy()
    environment["PATH"] = f"{bin_dir}:{environment['PATH']}"
    environment["FAKE_AWS_CALLS"] = str(calls)
    environment["OILSCOPE_GENERATED_ROOT"] = str(tmp_path / "generated")
    return environment, calls


def _command(*extra: str) -> list[str]:
    return [
        str(SCRIPT),
        "--provider",
        "aws",
        "--environment",
        "dev",
        "--deployment",
        "oilscope",
        "--region",
        "eu-west-1",
        "--config",
        str(AWS_CONFIG),
        *extra,
    ]


def _gcp_environment(tmp_path: Path) -> tuple[dict[str, str], Path]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    calls = tmp_path / "gcloud-calls.log"
    _write_executable(
        bin_dir / "gcloud",
        """#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "${FAKE_GCLOUD_CALLS}"
case "$1 $2" in
  "auth list")
    printf '%s\\n' 'operator@example.com'
    ;;
  "projects describe")
    printf '%s\\n' '123456789012'
    ;;
  "beta billing")
    printf '%s\\n' 'True'
    ;;
  "storage buckets"|"iam service-accounts"|"iam workload-identity-pools")
    if [[ "$*" == *" describe "* || "$*" == *" describe" ]]; then
      exit 1
    fi
    ;;
esac
""",
    )
    environment = os.environ.copy()
    environment["PATH"] = f"{bin_dir}:{environment['PATH']}"
    environment["FAKE_GCLOUD_CALLS"] = str(calls)
    environment["OILSCOPE_GENERATED_ROOT"] = str(tmp_path / "generated")
    return environment, calls


def _gcp_command(*extra: str) -> list[str]:
    return [
        str(SCRIPT),
        "--provider",
        "gcp",
        "--environment",
        "dev",
        "--deployment",
        "oilscope",
        "--region",
        "europe-west1",
        "--config",
        str(GCP_CONFIG),
        *extra,
    ]


def test_check_is_read_only_and_does_not_write_manifest(tmp_path: Path) -> None:
    environment, calls = _aws_environment(tmp_path)

    result = subprocess.run(  # noqa: S603 - test executes a repository script
        _command("--check"),
        cwd=REPOSITORY,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "No changes made" in result.stdout
    assert not (tmp_path / "generated").exists()
    invoked = calls.read_text(encoding="utf-8")
    for mutating_call in (
        "create-bucket",
        "create-role",
        "put-role-policy",
        "put-bucket",
    ):
        assert mutating_call not in invoked


def test_target_mismatch_fails_before_cloud_call(tmp_path: Path) -> None:
    environment, calls = _aws_environment(tmp_path)
    command = _command("--check")
    command[command.index("eu-west-1")] = "us-east-1"

    result = subprocess.run(  # noqa: S603 - test executes a repository script
        command,
        cwd=REPOSITORY,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode != 0
    assert "does not match --region" in result.stderr
    assert not calls.exists()


def test_help_does_not_require_cloud_tools() -> None:
    result = subprocess.run(  # noqa: S603 - test executes a repository script
        [str(SCRIPT), "--help"],
        cwd=REPOSITORY,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0
    assert "default mode is --check" in result.stdout


def test_gcp_check_detects_federation_without_mutation(tmp_path: Path) -> None:
    environment, calls = _gcp_environment(tmp_path)

    result = subprocess.run(  # noqa: S603 - test executes a repository script
        _gcp_command("--check"),
        cwd=REPOSITORY,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "Workload Identity Pool is missing" in result.stdout
    assert "GitHub OIDC provider is missing" in result.stdout
    assert "No changes made" in result.stdout
    assert not (tmp_path / "generated").exists()
    invoked = calls.read_text(encoding="utf-8")
    for mutating_call in (" create ", " add-iam-policy-binding", "services enable"):
        assert mutating_call not in invoked


def test_gcp_apply_creates_repository_scoped_federation(tmp_path: Path) -> None:
    environment, calls = _gcp_environment(tmp_path)

    result = subprocess.run(  # noqa: S603 - test executes a repository script
        _gcp_command("--yes"),
        cwd=REPOSITORY,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    invoked = calls.read_text(encoding="utf-8")
    assert "workload-identity-pools create oilscope-dev-github" in invoked
    assert "providers create-oidc github" in invoked
    assert "providers update-oidc github" in invoked
    assert "assertion.repository == 'ua-academy-projects/push-and-pray'" in invoked
    assert "roles/artifactregistry.writer" in invoked
    assert "roles/iam.workloadIdentityUser" in invoked

    manifest = tmp_path / "generated" / "dev" / "gcp" / "oilscope" / "foundation.json"
    contents = manifest.read_text(encoding="utf-8")
    assert "workloadIdentityPools/oilscope-dev-github/providers/github" in contents
    assert "ua-academy-projects/push-and-pray" in contents
