# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Push and Pray team
"""Derive gcp_compute settings from the shared project configuration JSON."""

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
short_description: OilScope inventory derived from the project configuration
version_added: "0.1.0"
author:
  - Push and Pray team
description:
  - Reads the shared project configuration JSON that Terraform also consumes,
    derives every environment-specific setting from it, and hands the result to
    C(google.cloud.gcp_compute), which performs the actual discovery.
  - The GCP project, the zone, the C(application) and C(environment) label
    filters and the bastion SSH port all come from that file, so no environment
    value is repeated in the inventory configuration and a copy per environment
    is unnecessary.
  - This wrapper exists because C(gcp_compute) neither reads the project
    configuration nor evaluates Jinja in its own configuration file - a
    template expression there is sent to the API as literal text.
extends_documentation_fragment:
  - inventory_cache
options:
  plugin:
    description:
      - Token that identifies this plugin. Must be
        C(oilscope.platform.oilscope_gcp).
    type: str
    required: true
    choices:
      - oilscope.platform.oilscope_gcp
  project_config_path:
    description:
      - Path to the project configuration JSON. A relative path resolves
        against the directory holding this inventory configuration file.
    type: str
    required: true
  workload_ssh_port:
    description:
      - Port the workload VMs listen on. The Terraform workload firewall rule
        opens 22 and nothing else, so the bastion's non-default port must not
        be applied to them.
    type: int
    default: 22
  bastion_role:
    description:
      - Value of the C(role) field identifying the bastion in the project
        configuration, and of the C(role) label on the instance.
    type: str
    default: bastion
  auth_kind:
    description:
      - Passed straight through to C(gcp_compute).
    type: str
    default: application
  vars_prefix:
    description:
      - Prefix for the raw instance fields C(gcp_compute) copies into host
        variables. Without one, its C(name) and C(tags) fields collide with
        names Ansible reserves.
    type: str
    default: gcp_
requirements:
  - google.cloud collection
  - google-auth
  - requests
notes:
  - Authenticates with Application Default Credentials. Run
    C(gcloud auth application-default login) on the controller first.
"""

EXAMPLES = r"""
# inventory/oilscope.yml
plugin: oilscope.platform.oilscope_gcp
project_config_path: ../../terraform/env/dev.json

cache: true
cache_plugin: ansible.builtin.jsonfile
cache_connection: ~/.cache/oilscope-inventory
cache_timeout: 300
"""

DELEGATE = "google.cloud.gcp_compute"
display = Display()


def plain(value):
    return str(value)


class InventoryModule(BaseInventoryPlugin, Cacheable):
    NAME = "oilscope.platform.oilscope_gcp"

    def verify_file(self, path):
        if not super().verify_file(path):
            return False

        return path.endswith(("oilscope.yml", "oilscope.yaml"))

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache=cache)
        self._read_config_data(path)

        if not HAS_YAML:
            raise AnsibleParserError("the oilscope_gcp inventory plugin requires PyYAML")

        config = self._load_project_config(path)
        settings = self._build_settings(config)
        generated = self._write_settings(settings)

        try:
            self._delegate(inventory, loader, generated, cache)
        finally:
            try:
                os.unlink(generated)
            except OSError as cleanup_error:
                display.vvv(f"could not remove {generated}: {cleanup_error}")

    def _load_project_config(self, path):
        config_path = self.get_option("project_config_path")

        if not os.path.isabs(config_path):
            config_path = os.path.join(os.path.dirname(os.path.abspath(path)), config_path)

        config_path = os.path.normpath(config_path)

        try:
            with open(config_path, "rb") as handle:
                config = json.load(handle)
        except OSError as read_error:
            raise AnsibleParserError(
                f"could not read the project configuration at {config_path}: {read_error}"
            ) from read_error
        except ValueError as decode_error:
            raise AnsibleParserError(
                f"the project configuration at {config_path} is not valid JSON: {decode_error}"
            ) from decode_error

        if not isinstance(config, dict):
            raise AnsibleParserError(
                f"the project configuration at {config_path} must contain a JSON object"
            )

        return config

    def _require(self, config, key):
        value = config.get(key)

        if not value or not isinstance(value, str):
            raise AnsibleParserError(
                f"the project configuration must define a non-empty string {key!r}"
            )

        return value

    def _bastion_ssh_port(self, config):
        bastion_role = self.get_option("bastion_role")
        vms = config.get("vms")

        if not isinstance(vms, dict):
            raise AnsibleParserError("the project configuration must define a 'vms' object")

        ports = [
            vm.get("ssh_port")
            for vm in vms.values()
            if isinstance(vm, dict) and vm.get("role") == bastion_role
        ]

        if not ports:
            raise AnsibleParserError(
                f"the project configuration defines no VM with role {bastion_role!r}"
            )

        if len(ports) > 1:
            raise AnsibleParserError(
                f"the project configuration defines {len(ports)} VMs with role "
                f"{bastion_role!r}; expected one"
            )

        try:
            return int(ports[0])
        except (TypeError, ValueError) as port_error:
            raise AnsibleParserError(
                f"the {bastion_role!r} VM must define an integer ssh_port"
            ) from port_error

    def _build_settings(self, config):
        project_id = self._require(config, "project_id")
        zone = self._require(config, "zone")
        name_prefix = self._require(config, "name_prefix")
        environment = self._require(config, "environment")

        bastion_role = plain(self.get_option("bastion_role"))
        auth_kind = plain(self.get_option("auth_kind"))
        vars_prefix = plain(self.get_option("vars_prefix"))
        bastion_port = self._bastion_ssh_port(config)
        workload_port = int(self.get_option("workload_ssh_port"))

        is_bastion = f"labels.role | default('') == '{bastion_role}'"
        has_public = "networkInterfaces[0].accessConfigs | default([])"
        public = "networkInterfaces[0].accessConfigs[0].natIP"
        private = "networkInterfaces[0].networkIP"

        return {
            "plugin": DELEGATE,
            "projects": [plain(project_id)],
            "zones": [plain(zone)],
            "filters": [
                f"labels.application = {plain(name_prefix)}",
                f"labels.environment = {plain(environment)}",
            ],
            "auth_kind": auth_kind,
            "hostnames": ["name"],
            "vars_prefix": vars_prefix,
            "keyed_groups": [{"key": "labels.role", "prefix": "", "separator": ""}],
            "groups": {"workloads": f"labels.role is defined and labels.role != '{bastion_role}'"},
            "compose": {
                "internal_ip": private,
                "public_ip": f"{public} if {has_public} else ''",
                "ansible_host": f"{public} if {is_bastion} else {private}",
                "ansible_port": f"{bastion_port} if {is_bastion} else {workload_port}",
                "oilscope_role": "labels.role | default('')",
            },
        }

    def _write_settings(self, settings):
        digest = hashlib.sha256(json.dumps(settings, sort_keys=True).encode("utf-8")).hexdigest()
        generated = os.path.join(tempfile.gettempdir(), f"oilscope-{digest[:16]}.gcp.yml")

        try:
            with open(generated, "w") as handle:
                yaml.safe_dump(settings, handle, default_flow_style=False)
        except OSError as write_error:
            raise AnsibleParserError(
                f"could not write the generated gcp_compute settings to {generated}: {write_error}"
            ) from write_error

        return generated

    def _delegate(self, inventory, loader, generated, cache):
        from ansible.plugins.loader import inventory_loader

        delegate = inventory_loader.get(DELEGATE)

        if delegate is None:
            raise AnsibleParserError(
                f"the {DELEGATE} inventory plugin is unavailable; "
                "install the google.cloud collection"
            )

        for option in ("cache", "cache_plugin", "cache_connection", "cache_timeout"):
            try:
                delegate.set_option(option, self.get_option(option))
            except (AnsibleError, KeyError) as option_error:
                display.vvv(f"{DELEGATE} rejected the {option} option: {option_error}")

        delegate.parse(inventory, loader, generated, cache=cache)
