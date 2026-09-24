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

DOCUMENTATION = r"""
name: oilscope_azure
short_description: OilScope inventory derived from the project configuration
version_added: "0.3.0"
author:
  - Push and Pray team
description:
  - Derives the subscription, the resource group, the location, the
    C(application)/C(environment) tag filters and the bastion SSH port from the
    project configuration JSON that Terraform also reads, then hands them to
    C(azure.azcollection.azure_rm), which performs the discovery. No
    environment value is repeated here.
  - The wrapper exists for the same reason C(oilscope.platform.oilscope_aws)
    and C(oilscope.platform.oilscope_gcp) exist - C(azure_rm) neither reads
    that file nor evaluates Jinja in its own configuration file.
extends_documentation_fragment:
  - inventory_cache
options:
  plugin:
    description:
      - Token that identifies this plugin. Must be
        C(oilscope.platform.oilscope_azure).
    type: str
    required: true
    choices:
      - oilscope.platform.oilscope_azure
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
        the VM's C(role) tag.
    type: str
    default: bastion
  auth_source:
    description:
      - How C(azure_rm) authenticates. C(auto) accepts C(ARM_*) environment
        variables, a credential file, a managed identity or an C(az login)
        session, in that order.
    type: str
    default: auto
    choices:
      - auto
      - cli
      - env
      - credential_file
      - msi
requirements:
  - azure.azcollection collection >= 4.0.0
  - the Python packages listed in that collection's own requirements.txt
notes:
  - Credentials are never read from the project configuration. Only the
    non-secret C(clouds.azure.subscription_id) is passed through; the token
    itself comes from the environment or from C(az login).
  - Discovery is scoped to C(clouds.azure.resource_group_name) rather than the
    whole subscription. VMSS, Arc and Stack HCI discovery stay switched off.
  - C(include_host_filters) entries are ORed, so the location and the
    application/environment tag checks are combined into a single C(and)
    expression. Two separate entries would widen discovery rather than narrow
    it.
  - Every discovered host carries C(oilscope_cloud) (always C(azure)),
    C(oilscope_vm_key) (its key in the configuration's C(vms) object,
    recovered from the VM's own C(name)) and C(oilscope_role) (from its
    C(role) tag). Roles that need a VM's own configuration entry -
    C(resolve_secrets), C(secret_versions) - should read C(oilscope_vm_key)
    rather than parsing C(inventory_hostname) themselves. C(plain_host_names)
    only changes how a host is displayed; it is never the identity a secret is
    resolved from.
  - Sets the SSH connection variables itself, after discovery - there is no
    C(group_vars/) directory beside the inventory. Every host gets
    C(ansible_user) (C(OILSCOPE_SSH_USER), else the controller's own login),
    C(ansible_ssh_private_key_file) and C(ansible_ssh_common_args). The
    gcloud-managed key fallback is never provisioned on Azure, so
    C(OILSCOPE_SSH_KEY) is effectively required here. The bastion also gets
    C(ansible_port), which C(OILSCOPE_BASTION_CONNECT_PORT) overrides.
  - Azure's cloud-init writes the bastion's final SSH port during first boot,
    so unlike a bootstrap on the other two clouds there is normally no window
    in which the bastion still answers on 22.
"""

EXAMPLES = r"""
# inventory/oilscope-azure.yml - the path comes from OILSCOPE_PROJECT_CONFIG or
# the option default, so it is deliberately not set here.
plugin: oilscope.platform.oilscope_azure
cache: true
cache_plugin: ansible.builtin.jsonfile
cache_connection: ~/.cache/oilscope-inventory-azure
cache_timeout: 300
"""

DELEGATE = "azure.azcollection.azure_rm"
display = Display()


class InventoryModule(BaseInventoryPlugin, Cacheable):
    NAME = "oilscope.platform.oilscope_azure"

    def verify_file(self, path):
        return super().verify_file(path) and path.endswith(
            ("oilscope-azure.yml", "oilscope-azure.yaml")
        )

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache=cache)
        self._read_config_data(path)

        if not HAS_YAML:
            raise AnsibleParserError("the oilscope_azure inventory plugin requires PyYAML")

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

        validate_inventory_hosts(inventory, config, "Azure")
        apply_connection_vars(inventory, config, plain(self.get_option("bastion_role")), "Azure")

    def _build_settings(self, config):
        region_key = require_str(config, "region")
        name_prefix = require_str(config, "name_prefix")
        environment = require_str(config, "environment")
        subscription_id = require_str(config, "clouds", "azure", "subscription_id")
        resource_group = require_str(config, "clouds", "azure", "resource_group_name")
        location = require_str(config, "region_map", region_key, "azure", "location")

        bastion_role = plain(self.get_option("bastion_role"))
        bastion_port = compute_bastion_ssh_port(config, bastion_role)
        vm_key_pattern = vm_key_regex(name_prefix, environment)

        # A VM with no tags at all has tags = None, and `tags.role` on None is
        # a template error rather than a miss - which fail_on_template_errors
        # would (correctly) turn into a hard failure. Reading through a
        # defaulted dict keeps an untagged stray VM a non-match instead.
        role = "(tags | default({}, true)).get('role', '')"
        application = "(tags | default({}, true)).get('application', '')"
        tag_environment = "(tags | default({}, true)).get('environment', '')"
        is_bastion = f"{role} == '{bastion_role}'"
        # azure_rm exposes a list despite this variable's singular name.
        # Select the primary address; private-only VMs have an empty list.
        public = "public_ipv4_address | default([], true) | first | default('', true)"
        private = "private_ipv4_addresses[0]"

        return {
            "plugin": DELEGATE,
            "auth_source": plain(self.get_option("auth_source")),
            "subscription_id": plain(subscription_id),
            # Scope the query to this deployment's own resource group. VMSS,
            # Arc and Stack HCI are not part of this architecture and stay
            # switched off rather than discovered and then filtered out.
            "include_vm_resource_groups": [plain(resource_group)],
            "include_vmss_resource_groups": [],
            "include_arc_resource_groups": [],
            "include_hcivm_resource_groups": [],
            # One expression, not three entries: this list is ORed, so three
            # entries would admit any VM matching any one of them.
            "include_host_filters": [
                f"location == '{plain(location)}' and "
                f"{application} == '{plain(name_prefix)}' and "
                f"{tag_environment} == '{plain(environment)}'"
            ],
            # Keeps azure_rm's own exclusion of stopped and half-provisioned
            # VMs, which replacing this list would silently drop.
            "default_host_filters": [
                'powerstate != "running"',
                'provisioning_state != "succeeded"',
            ],
            "fail_on_template_errors": True,
            # Presentation only. The resource group is an exact scope and VM
            # names are unique inside it, so the hash suffix adds nothing -
            # and oilscope_vm_key is still derived from `name` below, never
            # from the inventory alias.
            "plain_host_names": True,
            "keyed_groups": [{"key": role, "prefix": "", "separator": ""}],
            "conditional_groups": {"workloads": f"{role} not in ['', '{bastion_role}']"},
            "hostvar_expressions": {
                "internal_ip": private,
                "public_ip": public,
                "ansible_host": f"({public}) if ({is_bastion}) else ({private})",
                "bastion_ssh_port": f"'{bastion_port}'",
                "oilscope_role": role,
                "oilscope_cloud": "'azure'",
                "oilscope_vm_key": f"name | regex_replace('{vm_key_pattern}', '')",
                "oilscope_vm_id": "id",
            },
        }

    def _write_settings(self, settings):
        digest = hashlib.sha256(json.dumps(settings, sort_keys=True).encode("utf-8")).hexdigest()
        # azure_rm refuses any configuration file whose name does not end in
        # azure_rm.yml/.yaml, so the generated file cannot follow the
        # <digest>.<cloud>.yml shape the other two plugins use.
        generated = os.path.join(tempfile.gettempdir(), f"oilscope-{digest[:16]}.azure_rm.yml")

        try:
            with open(generated, "w") as handle:
                yaml.safe_dump(settings, handle, default_flow_style=False)
        except OSError as write_error:
            raise AnsibleParserError(
                f"could not write the generated azure_rm settings to {generated}: {write_error}"
            ) from write_error

        return generated

    def _delegate(self, inventory, loader, generated, cache):
        from ansible.plugins.loader import inventory_loader

        delegate = inventory_loader.get(DELEGATE)

        if delegate is None:
            raise AnsibleParserError(
                f"the {DELEGATE} inventory plugin is unavailable; "
                "install the azure.azcollection collection"
            )

        for option in ("cache", "cache_plugin", "cache_connection", "cache_timeout"):
            try:
                delegate.set_option(option, self.get_option(option))
            except (AnsibleError, KeyError) as option_error:
                display.vvv(f"{DELEGATE} rejected the {option} option: {option_error}")

        delegate.parse(inventory, loader, generated, cache=cache)
