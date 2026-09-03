# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Push and Pray team
"""Build a multi-cloud inventory from the shared project configuration JSON."""

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
except ImportError:  # pragma: no cover - PyYAML ships with ansible-core
    HAS_YAML = False

# Ansible requires inventory plugins to expose this variable.
DOCUMENTATION = r"""
name: oilscope_gcp
short_description: OilScope multi-cloud inventory derived from the project configuration
version_added: "0.1.0"
author:
  - Push and Pray team
description:
  - Reads the same project configuration JSON as Terraform and applies the
    C(default_cloud) plus optional per-VM C(cloud) override.
  - Delegates GCP discovery to C(google.cloud.gcp_compute) and AWS discovery to
    C(amazon.aws.aws_ec2). A delegate is not invoked when no configured VM uses
    that cloud.
  - Filters both providers by the managed C(application), C(environment), and
    C(cloud) label or tag, then creates the same role groups and host variables
    for both providers.
extends_documentation_fragment:
  - inventory_cache
options:
  plugin:
    description:
      - Token that identifies this plugin. The historical name is retained for
        compatibility even though the plugin now discovers both GCP and AWS.
    type: str
    required: true
    choices:
      - oilscope.platform.oilscope_gcp
  project_config_path:
    description:
      - Path to the shared project configuration JSON. Absolute paths are used
        as given; relative paths are tried from the working directory and then
        from the inventory file's directory.
      - Set C(OILSCOPE_PROJECT_CONFIG) for a configuration kept elsewhere. A
        value in the inventory file takes precedence over the environment.
    type: str
    required: false
    default: ../../terraform/env/dev.json
    env:
      - name: OILSCOPE_PROJECT_CONFIG
  workload_ssh_port:
    description:
      - SSH port used by workload VMs. The configured bastion port applies only
        to the bastion.
    type: int
    default: 22
  bastion_role:
    description:
      - Value of C(role) identifying the bastion.
    type: str
    default: bastion
  auth_kind:
    description:
      - Authentication mode passed to C(google.cloud.gcp_compute).
    type: str
    default: application
  vars_prefix:
    description:
      - Prefix applied to raw GCP instance fields to avoid reserved names.
    type: str
    default: gcp_
requirements:
  - google.cloud collection
  - amazon.aws collection
  - google-auth
  - requests
  - boto3
  - botocore
notes:
  - GCP uses Application Default Credentials by default.
  - AWS uses the normal boto3 credential chain, including C(AWS_PROFILE).
"""

EXAMPLES = r"""
# inventory/oilscope.yml
plugin: oilscope.platform.oilscope_gcp
cache: true
cache_plugin: ansible.builtin.jsonfile
cache_connection: ~/.cache/oilscope-inventory
cache_timeout: 300
"""

SUPPORTED_CLOUDS = ("gcp", "aws")
DELEGATES = {
    "gcp": "google.cloud.gcp_compute",
    "aws": "amazon.aws.aws_ec2",
}
FILE_SUFFIXES = {
    "gcp": "gcp.yml",
    "aws": "aws_ec2.yml",
}
display = Display()


def plain(value):
    return str(value)


class InventoryModule(BaseInventoryPlugin, Cacheable):
    NAME = "oilscope.platform.oilscope_gcp"

    def verify_file(self, path):
        return super().verify_file(path) and path.endswith(("oilscope.yml", "oilscope.yaml"))

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache=cache)
        self._read_config_data(path)

        if not HAS_YAML:
            raise AnsibleParserError("the oilscope inventory plugin requires PyYAML")

        config = self._load_project_config(path)
        settings_by_cloud = self._build_settings(config)
        generated_files = []

        try:
            for cloud, settings in settings_by_cloud.items():
                generated = self._write_settings(cloud, settings)
                generated_files.append(generated)
                self._delegate(cloud, inventory, loader, generated, cache)
        finally:
            for generated in generated_files:
                try:
                    os.unlink(generated)
                except OSError as cleanup_error:
                    display.vvv(f"could not remove {generated}: {cleanup_error}")

    def _resolve_config_path(self, path):
        configured = plain(self.get_option("project_config_path"))

        if os.path.isabs(configured):
            return os.path.normpath(configured)

        from_cwd = os.path.abspath(configured)

        if os.path.isfile(from_cwd):
            return from_cwd

        beside = os.path.join(os.path.dirname(os.path.abspath(path)), configured)
        return os.path.normpath(beside)

    def _load_project_config(self, path):
        config_path = self._resolve_config_path(path)

        try:
            with open(config_path, "rb") as handle:
                config = json.load(handle)
        except (OSError, ValueError) as error:
            raise AnsibleParserError(
                f"could not load the project configuration at {config_path}: {error}"
            ) from error

        if not isinstance(config, dict):
            raise AnsibleParserError(
                f"the project configuration at {config_path} must contain a JSON object"
            )

        return config

    def _require_string(self, mapping, key, context="project configuration"):
        value = mapping.get(key) if isinstance(mapping, dict) else None

        if not isinstance(value, str) or not value:
            raise AnsibleParserError(f"{context} must define a non-empty string {key!r}")

        return value

    def _require_mapping(self, mapping, key, context="project configuration"):
        value = mapping.get(key) if isinstance(mapping, dict) else None

        if not isinstance(value, dict):
            raise AnsibleParserError(f"{context} must define an object {key!r}")

        return value

    def _selected_vms_by_cloud(self, config):
        default_cloud = self._require_string(config, "default_cloud")

        if default_cloud not in SUPPORTED_CLOUDS:
            raise AnsibleParserError(
                f"default_cloud must be one of {', '.join(SUPPORTED_CLOUDS)}"
            )

        vms = self._require_mapping(config, "vms")
        selected = {cloud: {} for cloud in SUPPORTED_CLOUDS}

        for name, vm in vms.items():
            if not isinstance(vm, dict):
                raise AnsibleParserError(f"vms.{name} must be an object")

            cloud = vm.get("cloud", default_cloud)

            if cloud not in selected:
                raise AnsibleParserError(
                    f"vms.{name}.cloud must be one of {', '.join(SUPPORTED_CLOUDS)}"
                )

            selected[cloud][name] = vm

        return selected

    def _provider_locations(self, config, selected_vms, cloud, field):
        regions = self._require_mapping(config, "regions")
        values = set()

        for name, vm in selected_vms.items():
            logical_region = self._require_string(vm, "region", f"vms.{name}")
            region_mapping = self._require_mapping(
                regions, logical_region, "project configuration regions"
            )
            cloud_mapping = self._require_mapping(
                region_mapping, cloud, f"regions.{logical_region}"
            )
            values.add(
                self._require_string(
                    cloud_mapping,
                    field,
                    f"regions.{logical_region}.{cloud}",
                )
            )

        return sorted(values)

    def _bastion_ssh_port(self, config):
        bastion_role = self.get_option("bastion_role")
        vms = self._require_mapping(config, "vms")
        ports = [
            vm.get("ssh_port")
            for vm in vms.values()
            if isinstance(vm, dict) and vm.get("role") == bastion_role
        ]

        if len(ports) != 1:
            raise AnsibleParserError(
                f"expected exactly one VM with role {bastion_role!r}, found {len(ports)}"
            )

        try:
            return int(ports[0])
        except (TypeError, ValueError) as port_error:
            raise AnsibleParserError(
                f"the {bastion_role!r} VM must define an integer ssh_port"
            ) from port_error

    def _common_values(self, config):
        return {
            "name_prefix": self._require_string(config, "name_prefix"),
            "environment": self._require_string(config, "environment"),
            "bastion_role": plain(self.get_option("bastion_role")),
            "bastion_port": self._bastion_ssh_port(config),
            "workload_port": int(self.get_option("workload_ssh_port")),
        }

    def _build_gcp_settings(self, config, selected_vms, common):
        clouds = self._require_mapping(config, "clouds")
        gcp = self._require_mapping(clouds, "gcp", "project configuration clouds")
        project_id = self._require_string(gcp, "project_id", "clouds.gcp")
        zones = self._provider_locations(config, selected_vms, "gcp", "zone")

        role = "labels.role | default('')"
        is_bastion = f"{role} == '{common['bastion_role']}'"
        has_public = "networkInterfaces[0].accessConfigs | default([])"
        public = "networkInterfaces[0].accessConfigs[0].natIP"
        private = "networkInterfaces[0].networkIP"

        return {
            "plugin": DELEGATES["gcp"],
            "projects": [plain(project_id)],
            "zones": zones,
            "filters": [
                "status = RUNNING",
                f"labels.application = {common['name_prefix']}",
                f"labels.environment = {common['environment']}",
                "labels.cloud = gcp",
            ],
            "auth_kind": plain(self.get_option("auth_kind")),
            "hostnames": ["name"],
            "vars_prefix": plain(self.get_option("vars_prefix")),
            "keyed_groups": [{"key": "labels.role", "prefix": "", "separator": ""}],
            "groups": {
                "workloads": (
                    f"labels.role is defined and labels.role != '{common['bastion_role']}'"
                )
            },
            "compose": {
                "internal_ip": private,
                "public_ip": f"{public} if {has_public} else ''",
                "ansible_host": f"{public} if {is_bastion} else {private}",
                "ansible_port": (
                    f"{common['bastion_port']} if {is_bastion} "
                    f"else {common['workload_port']}"
                ),
                "oilscope_role": role,
                "oilscope_cloud": "labels.cloud | default('')",
            },
        }

    def _build_aws_settings(self, config, selected_vms, common):
        regions = self._provider_locations(config, selected_vms, "aws", "region")
        role = "ec2_tags.role | default('')"
        is_bastion = f"{role} == '{common['bastion_role']}'"
        public = "public_ip_address | default('')"
        private = "private_ip_address"

        return {
            "plugin": DELEGATES["aws"],
            "regions": regions,
            "filters": {
                "instance-state-name": "running",
                "tag:application": common["name_prefix"],
                "tag:environment": common["environment"],
                "tag:cloud": "aws",
            },
            "hostnames": ["tag:Name"],
            "use_contrib_script_compatible_ec2_tag_keys": False,
            "keyed_groups": [{"key": "ec2_tags.role", "prefix": "", "separator": ""}],
            "groups": {
                "workloads": (
                    f"ec2_tags.role is defined and "
                    f"ec2_tags.role != '{common['bastion_role']}'"
                )
            },
            "compose": {
                "internal_ip": private,
                "public_ip": public,
                "ansible_host": f"{public} if {is_bastion} else {private}",
                "ansible_port": (
                    f"{common['bastion_port']} if {is_bastion} "
                    f"else {common['workload_port']}"
                ),
                "oilscope_role": role,
                "oilscope_cloud": "ec2_tags.cloud | default('')",
            },
        }

    def _build_settings(self, config):
        selected = self._selected_vms_by_cloud(config)
        common = self._common_values(config)
        settings = {}

        if selected["gcp"]:
            settings["gcp"] = self._build_gcp_settings(config, selected["gcp"], common)

        if selected["aws"]:
            settings["aws"] = self._build_aws_settings(config, selected["aws"], common)

        return settings

    def _write_settings(self, cloud, settings):
        digest = hashlib.sha256(json.dumps(settings, sort_keys=True).encode("utf-8")).hexdigest()
        suffix = FILE_SUFFIXES[cloud]
        generated = os.path.join(tempfile.gettempdir(), f"oilscope-{digest[:16]}.{suffix}")

        try:
            with open(generated, "w") as handle:
                yaml.safe_dump(settings, handle, default_flow_style=False)
        except OSError as write_error:
            raise AnsibleParserError(
                f"could not write generated {DELEGATES[cloud]} settings to "
                f"{generated}: {write_error}"
            ) from write_error

        return generated

    def _delegate(self, cloud, inventory, loader, generated, cache):
        from ansible.plugins.loader import inventory_loader

        delegate_name = DELEGATES[cloud]
        delegate = inventory_loader.get(delegate_name)

        if delegate is None:
            collection = "google.cloud" if cloud == "gcp" else "amazon.aws"
            raise AnsibleParserError(
                f"the {delegate_name} inventory plugin is unavailable; "
                f"install the {collection} collection"
            )

        for option in ("cache", "cache_plugin", "cache_connection", "cache_timeout"):
            try:
                delegate.set_option(option, self.get_option(option))
            except (AnsibleError, KeyError) as option_error:
                display.vvv(f"{delegate_name} rejected the {option} option: {option_error}")

        delegate.parse(inventory, loader, generated, cache=cache)
