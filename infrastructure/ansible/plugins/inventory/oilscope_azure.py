# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Push and Pray team
"""Derive azure_rm settings from the shared project configuration JSON."""

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

# Ansible requires this metadata at module load time.
DOCUMENTATION = r"""
name: oilscope_azure
short_description: OilScope Azure inventory derived from the project configuration
version_added: "0.1.0"
author:
  - Push and Pray team
description:
  - Derives the Azure resource group and VM tag filters from the project
    configuration JSON that Terraform also reads, then hands them to
    C(azure.azcollection.azure_rm), which performs discovery.
extends_documentation_fragment:
  - inventory_cache
options:
  plugin:
    description:
      - Token that identifies this plugin.
    type: str
    required: true
    choices:
      - oilscope_azure
  project_config_path:
    description:
      - Path to the project configuration JSON.
      - Can be provided through C(OILSCOPE_PROJECT_CONFIG).
    type: str
    required: true
    env:
      - name: OILSCOPE_PROJECT_CONFIG
requirements:
  - azure.azcollection collection
  - Python packages from azure.azcollection/requirements.txt
notes:
  - Uses the active Azure CLI session. Run C(az login) and select the target
    subscription with C(az account set) before discovery.
"""

EXAMPLES = r"""
# inventory/oilscope.azure.yml
plugin: oilscope_azure
cache: false
"""

DELEGATE = "azure.azcollection.azure_rm"
display = Display()


def plain(value):
    return str(value)


class InventoryModule(BaseInventoryPlugin, Cacheable):
    NAME = "oilscope_azure"

    def verify_file(self, path):
        return super().verify_file(path) and path.endswith(
            ("oilscope.azure.yml", "oilscope.azure.yaml")
        )

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache=cache)
        self._read_config_data(path)

        if not HAS_YAML:
            raise AnsibleParserError(
                "the oilscope_azure inventory plugin requires PyYAML"
            )

        config = self._load_project_config(path)
        if not self._uses_azure(config):
            return

        settings = self._build_settings(config)
        generated = self._write_settings(settings)

        try:
            self._delegate(inventory, loader, generated, cache)
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

    def _uses_azure(self, config):
        vms = config.get("vms")
        default_cloud = config.get("default_cloud")

        if not isinstance(vms, dict):
            raise AnsibleParserError(
                "the project configuration must define a 'vms' object"
            )

        if default_cloud not in ("gcp", "aws", "azure"):
            raise AnsibleParserError(
                "the project configuration must define 'default_cloud' as "
                "'gcp', 'aws' or 'azure'"
            )

        return any(
            isinstance(vm, dict)
            and vm.get("cloud", default_cloud) == "azure"
            for vm in vms.values()
        )

    def _require(self, config, key):
        value = config.get(key)

        if not value or not isinstance(value, str):
            raise AnsibleParserError(
                f"the project configuration must define a non-empty string {key!r}"
            )

        return value

    def _build_settings(self, config):
        name_prefix = self._require(config, "name_prefix")
        environment = self._require(config, "environment")
        resource_group = f"{name_prefix}-{environment}"

        tag_filter = (
            f"tags.application is defined and "
            f"tags.application == '{name_prefix}' and "
            f"tags.environment is defined and "
            f"tags.environment == '{environment}'"
        )
        is_bastion = "tags.role | default('') == 'bastion'"
        private_ip = "private_ipv4_addresses | first"
        public_ip = "(public_ipv4_address | first) | default('')"

        return {
            "plugin": DELEGATE,
            "auth_source": "cli",
            "include_vm_resource_groups": [resource_group],
            "include_host_filters": [tag_filter],
            "hostnames": ["name"],
            "plain_host_names": True,
            "fail_on_template_errors": True,
            "keyed_groups": [
                {"key": "tags.role", "prefix": "", "separator": ""}
            ],
            "conditional_groups": {
                "vms": "tags.role is defined and tags.role != 'bastion'"
            },
            "hostvar_expressions": {
                "internal_ip": private_ip,
                "public_ip": public_ip,
                "ansible_host": f"({public_ip}) if {is_bastion} else {private_ip}",
                "oilscope_role": "tags.role | default('')",
                "oilscope_cloud": "'azure'",
            },
        }

    def _write_settings(self, settings):
        digest = hashlib.sha256(
            json.dumps(settings, sort_keys=True).encode("utf-8")
        ).hexdigest()
        generated = os.path.join(
            tempfile.gettempdir(), f"oilscope-{digest[:16]}.azure_rm.yml"
        )

        try:
            with open(generated, "w") as handle:
                yaml.safe_dump(settings, handle, default_flow_style=False)
        except OSError as write_error:
            raise AnsibleParserError(
                f"could not write generated azure_rm settings to {generated}: "
                f"{write_error}"
            ) from write_error

        return generated

    def _delegate(self, inventory, loader, generated, cache):
        from ansible.plugins.loader import inventory_loader

        delegate = inventory_loader.get(DELEGATE)

        if delegate is None:
            raise AnsibleParserError(
                f"the {DELEGATE} inventory plugin is unavailable; "
                "install azure.azcollection and its Python requirements"
            )

        for option in ("cache", "cache_plugin", "cache_connection", "cache_timeout"):
            try:
                delegate.set_option(option, self.get_option(option))
            except (AnsibleError, KeyError) as option_error:
                display.vvv(f"{DELEGATE} rejected the {option} option: {option_error}")

        delegate.parse(inventory, loader, generated, cache=cache)
