# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Push and Pray team
"""Derive GCP and AWS inventory settings from the shared project configuration."""

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

# DO NOT DELETE BECAUSE PLUGIN WILL FAIL
DOCUMENTATION = r"""
name: oilscope_gcp
short_description: OilScope multi-cloud inventory derived from project configuration
version_added: "0.1.0"
author:
  - Push and Pray team
description:
  - Reads the same project configuration JSON as Terraform, resolves each VM's
    effective cloud, and delegates discovery to C(google.cloud.gcp_compute) and
    C(amazon.aws.aws_ec2) for the clouds that have matching VMs.
  - Provider projects, regions, zones, names, labels, and tags are derived from
    the shared configuration rather than repeated in the inventory source.
extends_documentation_fragment:
  - inventory_cache
options:
  plugin:
    description:
      - Token that identifies this plugin.
    type: str
    required: true
    choices:
      - oilscope.platform.oilscope_gcp
  project_config_path:
    description:
      - Path to the project configuration JSON. Absolute is used as given;
        relative is tried against the working directory, then against this
        file's directory.
      - Set C(OILSCOPE_PROJECT_CONFIG) for a configuration kept elsewhere.
    type: str
    required: false
    default: ../../terraform/env/dev.json
    env:
      - name: OILSCOPE_PROJECT_CONFIG
  workload_ssh_port:
    description:
      - Port used by non-bastion VMs.
    type: int
    default: 22
  bastion_role:
    description:
      - Value of C(role) identifying the bastion.
    type: str
    default: bastion
  auth_kind:
    description:
      - Authentication mode passed to C(gcp_compute).
    type: str
    default: application
  vars_prefix:
    description:
      - Prefix for raw GCP instance fields copied into host variables.
    type: str
    default: gcp_
requirements:
  - google.cloud collection
  - amazon.aws collection
  - google-auth
  - requests
  - boto3
  - botocore
"""

EXAMPLES = r"""
plugin: oilscope.platform.oilscope_gcp
cache: true
cache_plugin: ansible.builtin.jsonfile
cache_connection: ~/.cache/oilscope-inventory
cache_timeout: 300
"""

DELEGATES = {
    "gcp": "google.cloud.gcp_compute",
    "aws": "amazon.aws.aws_ec2",
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

        for cloud, settings in settings_by_cloud.items():
            generated = self._write_settings(cloud, settings)
            try:
                self._delegate(cloud, inventory, loader, generated, cache)
            finally:
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

    def _require_string(self, value, path):
        if not value or not isinstance(value, str):
            raise AnsibleParserError(
                f"the project configuration must define a non-empty string {path!r}"
            )
        return value

    def _effective_vms(self, config):
        default_cloud = self._require_string(config.get("default_cloud"), "default_cloud")
        vms = config.get("vms")
        if not isinstance(vms, dict):
            raise AnsibleParserError("the project configuration must define a 'vms' object")

        selected = {cloud: {} for cloud in DELEGATES}
        for name, vm in vms.items():
            if not isinstance(vm, dict):
                raise AnsibleParserError(f"vms.{name} must be an object")
            cloud = vm.get("cloud", default_cloud)
            if cloud not in selected:
                raise AnsibleParserError(f"vms.{name} selects unsupported cloud {cloud!r}")
            selected[cloud][name] = vm
        return selected

    def _bastion_ssh_port(self, config):
        bastion_role = self.get_option("bastion_role")
        ports = [
            vm.get("ssh_port")
            for vm in config["vms"].values()
            if vm.get("role") == bastion_role
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

    def _resource_names(self, config, vms):
        prefix = self._require_string(config.get("name_prefix"), "name_prefix")
        environment = self._require_string(config.get("environment"), "environment")
        return [f"{prefix}-{environment}-{name}" for name in vms]

    def _gcp_name_filter(self, names):
        return " OR ".join(f"(name = {name})" for name in names)

    def _locations(self, config, vms, cloud, key):
        locations = config.get("locations", {})
        try:
            return sorted({plain(locations[vm["location"]][cloud][key]) for vm in vms.values()})
        except (KeyError, TypeError) as error:
            raise AnsibleParserError(
                f"every {cloud} VM location must define {cloud}.{key}"
            ) from error

    def _common(self, config):
        labels = config.get("common_labels", {})
        return {
            "application": self._require_string(labels.get("application"), "common_labels.application"),
            "environment": self._require_string(labels.get("environment"), "common_labels.environment"),
            "bastion_role": plain(self.get_option("bastion_role")),
            "bastion_port": self._bastion_ssh_port(config),
            "workload_port": int(self.get_option("workload_ssh_port")),
        }

    def _gcp_settings(self, config, vms, common):
        project_id = self._require_string(
            config.get("clouds", {}).get("gcp", {}).get("project_id"),
            "clouds.gcp.project_id",
        )
        names = self._resource_names(config, vms)
        is_bastion = f"labels.role | default('') == '{common['bastion_role']}'"
        has_public = "networkInterfaces[0].accessConfigs | default([])"
        public = "networkInterfaces[0].accessConfigs[0].natIP"
        private = "networkInterfaces[0].networkIP"

        return {
            "plugin": DELEGATES["gcp"],
            "projects": [project_id],
            "zones": self._locations(config, vms, "gcp", "zone"),
            "filters": [
                self._gcp_name_filter(names),
                f"labels.application = {common['application']}",
                f"labels.environment = {common['environment']}",
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
                    f"{common['bastion_port']} if {is_bastion} else {common['workload_port']}"
                ),
                "oilscope_role": "labels.role | default('')",
                "oilscope_cloud": "'gcp'",
            },
        }

    def _aws_settings(self, config, vms, common):
        names = self._resource_names(config, vms)
        is_bastion = f"tags.role | default('') == '{common['bastion_role']}'"
        public = "public_ip_address | default('')"
        private = "private_ip_address"

        return {
            "plugin": DELEGATES["aws"],
            "regions": self._locations(config, vms, "aws", "region"),
            "filters": {
                "instance-state-name": "running",
                "tag:Name": names,
                "tag:application": common["application"],
                "tag:environment": common["environment"],
            },
            "hostnames": ["tag:Name"],
            "keyed_groups": [{"key": "tags.role", "prefix": "", "separator": ""}],
            "groups": {
                "workloads": f"tags.role is defined and tags.role != '{common['bastion_role']}'"
            },
            "compose": {
                "internal_ip": private,
                "public_ip": public,
                "ansible_host": f"{public} if {is_bastion} else {private}",
                "ansible_port": (
                    f"{common['bastion_port']} if {is_bastion} else {common['workload_port']}"
                ),
                "oilscope_role": "tags.role | default('')",
                "oilscope_cloud": "'aws'",
            },
        }

    def _build_settings(self, config):
        selected = self._effective_vms(config)
        common = self._common(config)
        builders = {
            "gcp": self._gcp_settings,
            "aws": self._aws_settings,
        }
        return {
            cloud: builders[cloud](config, vms, common)
            for cloud, vms in selected.items()
            if vms
        }

    def _write_settings(self, cloud, settings):
        digest = hashlib.sha256(json.dumps(settings, sort_keys=True).encode("utf-8")).hexdigest()
        suffixes = {"gcp": "gcp", "aws": "aws_ec2"}
        generated = os.path.join(
            tempfile.gettempdir(), f"oilscope-{digest[:16]}.{suffixes[cloud]}.yml"
        )
        try:
            with open(generated, "w") as handle:
                yaml.safe_dump(settings, handle, default_flow_style=False)
        except OSError as write_error:
            raise AnsibleParserError(
                f"could not write generated {cloud} inventory settings to {generated}: {write_error}"
            ) from write_error
        return generated

    def _delegate(self, cloud, inventory, loader, generated, cache):
        from ansible.plugins.loader import inventory_loader

        delegate_name = DELEGATES[cloud]
        delegate = inventory_loader.get(delegate_name)
        if delegate is None:
            raise AnsibleParserError(
                f"the {delegate_name} inventory plugin is unavailable; install its collection"
            )

        for option in ("cache", "cache_plugin", "cache_connection", "cache_timeout"):
            try:
                delegate.set_option(option, self.get_option(option))
            except (AnsibleError, KeyError) as option_error:
                display.vvv(f"{delegate_name} rejected the {option} option: {option_error}")

        delegate.parse(inventory, loader, generated, cache=cache)
