# SPDX-License-Identifier: GPL-2.0-or-later
"""Build one Ansible inventory from the shared AWS/GCP project configuration."""

import hashlib
import json
import os
import tempfile

from ansible.errors import AnsibleError, AnsibleParserError
from ansible.plugins.inventory import BaseInventoryPlugin, Cacheable
from ansible.utils.display import Display

try:
    import yaml

    HAS_YAML = True
except ImportError:  # pragma: no cover
    HAS_YAML = False

DOCUMENTATION = r"""
name: oilscope_cloud
short_description: Multi-cloud OilScope inventory from project configuration
version_added: "0.2.0"
author:
  - Push and Pray team
description:
  - Reads the same project configuration JSON as Terraform.
  - Discovers only clouds selected by default_cloud and per-VM cloud overrides.
  - Delegates to google.cloud.gcp_compute and amazon.aws.aws_ec2.
extends_documentation_fragment:
  - inventory_cache
options:
  plugin:
    description: Token identifying this plugin.
    type: str
    required: true
    choices: [oilscope.platform.oilscope_cloud]
  project_config_path:
    description: Shared project configuration JSON path.
    type: str
    required: false
    default: ../../terraform/env/dev.json
    env:
      - name: OILSCOPE_PROJECT_CONFIG
  workload_ssh_port:
    description: SSH port used by workload hosts.
    type: int
    default: 22
  bastion_connect_port:
    description: Temporary SSH port used to bootstrap a new bastion.
    type: int
    required: false
    env:
      - name: OILSCOPE_BASTION_CONNECT_PORT
  auth_kind:
    description: Authentication mode forwarded to gcp_compute.
    type: str
    default: application
  vars_prefix:
    description: Prefix for raw GCP host variables.
    type: str
    default: gcp_
requirements:
  - google.cloud collection and google-auth for GCP
  - amazon.aws collection and boto3 for AWS
"""

EXAMPLES = r"""
plugin: oilscope.platform.oilscope_cloud
cache: false
"""

display = Display()


def plain(value):
    return str(value)


class InventoryModule(BaseInventoryPlugin, Cacheable):
    NAME = "oilscope.platform.oilscope_cloud"

    def verify_file(self, path):
        return super().verify_file(path) and path.endswith(("oilscope.yml", "oilscope.yaml"))

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache=cache)
        self._read_config_data(path)

        if not HAS_YAML:
            raise AnsibleParserError("the oilscope_cloud inventory plugin requires PyYAML")

        config = self._load_project_config(path)
        settings_by_cloud = self._build_settings(config)
        generated_files = []

        try:
            for cloud, settings in settings_by_cloud.items():
                generated = self._write_settings(cloud, settings)
                generated_files.append(generated)
                self._delegate(inventory, loader, settings["plugin"], generated, cache)
        finally:
            for generated in generated_files:
                try:
                    os.unlink(generated)
                except OSError as cleanup_error:
                    display.vvv(f"could not remove {generated}: {cleanup_error}")

    def _resolve_config_path(self, inventory_path):
        configured = plain(self.get_option("project_config_path"))
        if os.path.isabs(configured):
            return os.path.normpath(configured)

        from_cwd = os.path.abspath(configured)
        if os.path.isfile(from_cwd):
            return from_cwd

        return os.path.normpath(
            os.path.join(os.path.dirname(os.path.abspath(inventory_path)), configured)
        )

    def _load_project_config(self, inventory_path):
        config_path = self._resolve_config_path(inventory_path)
        try:
            with open(config_path, "rb") as handle:
                config = json.load(handle)
        except (OSError, ValueError) as error:
            raise AnsibleParserError(
                f"could not load project configuration at {config_path}: {error}"
            ) from error

        if not isinstance(config, dict):
            raise AnsibleParserError("project configuration must contain a JSON object")
        return config

    @staticmethod
    def _require(mapping, key, context):
        value = mapping.get(key)
        if not isinstance(value, str) or not value:
            raise AnsibleParserError(f"{context}.{key} must be a non-empty string")
        return value

    @staticmethod
    def _effective_cloud(config, vm):
        return plain(vm.get("cloud", config.get("default_cloud", ""))).lower()

    def _bastion_port(self, config, cloud):
        ports = [
            vm.get("ssh_port")
            for vm in config.get("vms", {}).values()
            if isinstance(vm, dict)
            and vm.get("role") == "bastion"
            and self._effective_cloud(config, vm) == cloud
        ]
        if len(ports) > 1:
            raise AnsibleParserError(f"cloud {cloud!r} has more than one bastion")
        if not ports:
            return 22
        try:
            return int(ports[0])
        except (TypeError, ValueError) as error:
            raise AnsibleParserError(f"the {cloud} bastion must define integer ssh_port") from error

    def _build_settings(self, config):
        default_cloud = self._require(config, "default_cloud", "config").lower()
        vms = config.get("vms")
        clouds = config.get("clouds")
        defaults = config.get("defaults")

        if default_cloud not in {"aws", "gcp"}:
            raise AnsibleParserError("default_cloud must be either 'aws' or 'gcp'")
        if not isinstance(vms, dict) or not isinstance(clouds, dict):
            raise AnsibleParserError("config must define vms and clouds objects")
        if not isinstance(defaults, dict):
            raise AnsibleParserError("config must define a defaults object")

        used_clouds = {self._effective_cloud(config, vm) for vm in vms.values()}
        unsupported = used_clouds - {"aws", "gcp"}
        if unsupported:
            raise AnsibleParserError(
                f"unsupported cloud override(s): {', '.join(sorted(unsupported))}"
            )

        prefix = self._require(config, "name_prefix", "config")
        environment = self._require(config, "environment", "config")
        workload_port = int(self.get_option("workload_ssh_port"))
        location_profile = self._require(defaults, "location_profile", "defaults")
        result = {}

        if "gcp" in used_clouds:
            gcp = clouds.get("gcp", {})
            location = gcp.get("locations", {}).get(location_profile, {})
            project_id = self._require(gcp, "project_id", "clouds.gcp")
            zone = self._require(location, "zone", f"clouds.gcp.locations.{location_profile}")
            bastion_port = self._bastion_port(config, "gcp")
            bastion_connect_port = self.get_option("bastion_connect_port") or bastion_port
            role = "labels.role | default('')"
            has_public = "networkInterfaces[0].accessConfigs | default([])"
            public = "networkInterfaces[0].accessConfigs[0].natIP"
            private = "networkInterfaces[0].networkIP"

            result["gcp"] = {
                "plugin": "google.cloud.gcp_compute",
                "projects": [project_id],
                "zones": [zone],
                "filters": [
                    f"labels.application = {prefix}",
                    f"labels.environment = {environment}",
                    "labels.cloud = gcp",
                ],
                "auth_kind": plain(self.get_option("auth_kind")),
                "hostnames": ["name"],
                "vars_prefix": plain(self.get_option("vars_prefix")),
                "keyed_groups": [{"key": "labels.role", "prefix": "", "separator": ""}],
                "groups": {
                    "workloads": f"{role} != 'bastion'",
                    "gcp": "labels.cloud == 'gcp'",
                    "gcp_bastion": f"{role} == 'bastion'",
                },
                "compose": {
                    "internal_ip": private,
                    "public_ip": f"{public} if {has_public} else ''",
                    "ansible_host": f"{public} if {role} == 'bastion' else {private}",
                    "ansible_port": (
                        f"{bastion_connect_port} if {role} == 'bastion' else {workload_port}"
                    ),
                    "oilscope_bastion_ssh_port": plain(bastion_port),
                    "oilscope_role": role,
                    "oilscope_cloud": "'gcp'",
                    "oilscope_vm_key": "labels.vm_name | default('')",
                },
            }

        if "aws" in used_clouds:
            aws = clouds.get("aws", {})
            location = aws.get("locations", {}).get(location_profile, {})
            region = self._require(location, "region", f"clouds.aws.locations.{location_profile}")
            bastion_port = self._bastion_port(config, "aws")
            bastion_connect_port = self.get_option("bastion_connect_port") or bastion_port
            role = "tags.role | default('')"

            result["aws"] = {
                "plugin": "amazon.aws.aws_ec2",
                "regions": [region],
                "filters": {
                    "tag:application": prefix,
                    "tag:environment": environment,
                    "tag:cloud": "aws",
                    "instance-state-name": "running",
                },
                "hostnames": ["tag:Name"],
                "keyed_groups": [{"key": "tags.role", "prefix": "", "separator": ""}],
                "groups": {
                    "workloads": f"{role} != 'bastion'",
                    "aws": "tags.cloud == 'aws'",
                    "aws_bastion": f"{role} == 'bastion'",
                },
                "compose": {
                    "internal_ip": "private_ip_address",
                    "public_ip": "public_ip_address | default('')",
                    "ansible_host": (
                        f"public_ip_address if {role} == 'bastion' else private_ip_address"
                    ),
                    "ansible_port": (
                        f"{bastion_connect_port} if {role} == 'bastion' else {workload_port}"
                    ),
                    "oilscope_bastion_ssh_port": plain(bastion_port),
                    "oilscope_role": role,
                    "oilscope_cloud": "'aws'",
                    "oilscope_vm_key": "tags.vm_name | default('')",
                },
                "strict": True,
            }

        return result

    @staticmethod
    def _write_settings(cloud, settings):
        digest = hashlib.sha256(json.dumps(settings, sort_keys=True).encode("utf-8")).hexdigest()
        generated = os.path.join(tempfile.gettempdir(), f"oilscope-{digest[:16]}.{cloud}.yml")
        try:
            with open(generated, "w", encoding="utf-8") as handle:
                yaml.safe_dump(settings, handle, default_flow_style=False)
        except OSError as error:
            raise AnsibleParserError(f"could not write generated inventory: {error}") from error
        return generated

    def _delegate(self, inventory, loader, delegate_name, generated, cache):
        from ansible.plugins.loader import inventory_loader

        delegate = inventory_loader.get(delegate_name)
        if delegate is None:
            raise AnsibleParserError(
                f"the {delegate_name} inventory plugin is unavailable; "
                "install infrastructure/ansible/requirements.yml"
            )

        for option in ("cache", "cache_plugin", "cache_connection", "cache_timeout"):
            try:
                delegate.set_option(option, self.get_option(option))
            except (AnsibleError, KeyError) as error:
                display.vvv(f"{delegate_name} rejected {option}: {error}")

        delegate.parse(inventory, loader, generated, cache=cache)
