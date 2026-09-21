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

from ansible_collections.oilscope.platform.plugins.module_utils.oilscope_inventory import (
    bastion_ssh_port as compute_bastion_ssh_port,
)
from ansible_collections.oilscope.platform.plugins.module_utils.oilscope_inventory import (
    apply_connection_vars,
    load_project_config,
    plain,
    require_str,
    resolve_config_path,
    validate_inventory_hosts,
    vm_key_regex,
)

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
  - Derives the GCP project, zone, C(application) and C(environment) label
    filters and the bastion SSH port from the project configuration JSON that
    Terraform also reads, then hands them to C(google.cloud.gcp_compute), which
    performs the discovery. No environment value is repeated here.
  - The wrapper exists because C(gcp_compute) neither reads that file nor
    evaluates Jinja in its own configuration - a template expression there
    reaches the API as literal text.
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
      - Path to the project configuration JSON. Absolute is used as given;
        relative is tried against the working directory, then against this
        file's directory.
      - Set C(OILSCOPE_PROJECT_CONFIG) for a configuration kept elsewhere. A
        value written into the inventory file wins over the environment, so
        leave the key out to make the variable effective.
    type: str
    required: false
    default: ../../terraform/env/dev.json
    env:
      - name: OILSCOPE_PROJECT_CONFIG
  bastion_role:
    description:
      - Value of C(role) identifying the bastion, in the configuration and in
        the instance label.
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
        variables; without one its C(name) and C(tags) collide with reserved
        names.
    type: str
    default: gcp_
requirements:
  - google.cloud collection
  - google-auth
  - requests
notes:
  - Authenticates with Application Default Credentials. Run
    C(gcloud auth application-default login) on the controller first.
  - Every discovered host carries C(oilscope_cloud) (always C(gcp)),
    C(oilscope_vm_key) (its key in the configuration's C(vms) object,
    recovered from the instance name) and C(oilscope_role). Roles that need a
    VM's own configuration entry - C(resolve_secrets), C(secret_versions) -
    should read C(oilscope_vm_key) rather than parsing C(inventory_hostname)
    themselves.
  - Sets the SSH connection variables itself, after discovery - there is no
    C(group_vars/) directory beside the inventory. Every host gets
    C(ansible_user) (C(OILSCOPE_SSH_USER), else the controller's own login),
    C(ansible_ssh_private_key_file) (C(OILSCOPE_SSH_KEY), else the
    gcloud-managed C(~/.ssh/google_compute_engine)) and
    C(ansible_ssh_common_args). The bastion also gets C(ansible_port), which
    C(OILSCOPE_BASTION_CONNECT_PORT) overrides for first-boot bootstrap.
    Workloads have no public address, so each gets an
    C(ansible_ssh_common_args) carrying a C(ProxyCommand) through the
    bastion's discovered address, plus C(oilscope_bastion_address) and
    C(oilscope_bastion_ssh_port) as data.
  - A workload's C(ProxyCommand) needs the bastion's discovered address, which
    a per-host C(compose) expression cannot see, so these are applied in
    Python once the delegate has finished rather than composed per host.
"""

EXAMPLES = r"""
# inventory/oilscope.yml - the path comes from OILSCOPE_PROJECT_CONFIG or the
# option default, so it is deliberately not set here.
plugin: oilscope.platform.oilscope_gcp
cache: true
cache_plugin: ansible.builtin.jsonfile
cache_connection: ~/.cache/oilscope-inventory
cache_timeout: 300
"""

DELEGATE = "google.cloud.gcp_compute"
display = Display()


class InventoryModule(BaseInventoryPlugin, Cacheable):
    NAME = "oilscope.platform.oilscope_gcp"

    def verify_file(self, path):
        return super().verify_file(path) and path.endswith(("oilscope.yml", "oilscope.yaml"))

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache=cache)
        self._read_config_data(path)

        if not HAS_YAML:
            raise AnsibleParserError("the oilscope_gcp inventory plugin requires PyYAML")

        config_path = resolve_config_path(plain(self.get_option("project_config_path")), path)
        config = load_project_config(config_path)
        settings = self._build_settings(config)
        generated = self._write_settings(settings)

        try:
            self._delegate(inventory, loader, generated, cache)
        finally:
            try:
                os.unlink(generated)
            except OSError as cleanup_error:
                display.vvv(f"could not remove {generated}: {cleanup_error}")

        validate_inventory_hosts(inventory, config, "GCP")
        apply_connection_vars(inventory, config, plain(self.get_option("bastion_role")), "GCP")

    def _build_settings(self, config):
        region_key = require_str(config, "region")
        name_prefix = require_str(config, "name_prefix")
        environment = require_str(config, "environment")
        project_id = require_str(config, "clouds", "gcp", "project_id")
        zone = require_str(config, "region_map", region_key, "gcp", "zone")

        bastion_role = plain(self.get_option("bastion_role"))
        auth_kind = plain(self.get_option("auth_kind"))
        vars_prefix = plain(self.get_option("vars_prefix"))
        bastion_port = compute_bastion_ssh_port(config, bastion_role)
        vm_key_pattern = vm_key_regex(name_prefix, environment)

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
                "bastion_ssh_port": str(bastion_port),
                "oilscope_role": "labels.role | default('')",
                "oilscope_cloud": "'gcp'",
                "oilscope_vm_key": f"name | regex_replace('{vm_key_pattern}', '')",
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
