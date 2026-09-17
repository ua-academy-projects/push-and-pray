from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
SCRIPT = REPOSITORY / "scripts" / "bootstrap-cloud.sh"
AWS_CONFIG = REPOSITORY / "configs" / "project-config.aws.json"


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
