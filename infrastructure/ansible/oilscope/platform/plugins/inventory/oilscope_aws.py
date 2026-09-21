# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Push and Pray team
"""Derive aws_ec2 settings from the shared project configuration JSON."""

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
name: oilscope_aws
short_description: OilScope inventory derived from the project configuration
version_added: "0.2.0"
author:
  - Push and Pray team
description:
  - Derives the AWS region, the C(application)/C(environment) tag filters and
    the bastion SSH port from the project configuration JSON that Terraform
    also reads, then hands them to C(amazon.aws.aws_ec2), which performs the
    discovery. No environment value is repeated here.
  - The wrapper exists for the same reason C(oilscope.platform.oilscope_gcp)
    exists for GCP - C(aws_ec2) neither reads that file nor evaluates Jinja in
    its own configuration file.
extends_documentation_fragment:
  - inventory_cache
options:
  plugin:
    description:
      - Token that identifies this plugin. Must be
        C(oilscope.platform.oilscope_aws).
    type: str
    required: true
    choices:
      - oilscope.platform.oilscope_aws
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
        the instance's C(role) tag.
    type: str
    default: bastion
requirements:
  - amazon.aws collection >= 11.2.0
  - boto3
  - botocore
notes:
  - Authenticates through the standard boto3 credential chain (environment
    variables, a shared credentials/config file, or an assumed/instance
    role) - there is no equivalent of gcp_compute's C(auth_kind) option to
    set here.
  - Every discovered host carries C(oilscope_cloud) (always C(aws)),
    C(oilscope_vm_key) (its key in the configuration's C(vms) object,
    recovered from the instance's C(Name) tag) and C(oilscope_role). Roles
    that need a VM's own configuration entry - C(resolve_secrets),
    C(secret_versions) - should read C(oilscope_vm_key) rather than parsing
    C(inventory_hostname) themselves.
  - Sets the SSH connection variables itself, after discovery - there is no
    C(group_vars/) directory beside the inventory. Every host gets
    C(ansible_user) (C(OILSCOPE_SSH_USER), else the controller's own login),
    C(ansible_ssh_private_key_file) (C(OILSCOPE_SSH_KEY); the gcloud-managed
    fallback is never provisioned on AWS, so the variable is effectively
    required here) and C(ansible_ssh_common_args). The bastion also gets
    C(ansible_port), which C(OILSCOPE_BASTION_CONNECT_PORT) overrides for
    first-boot bootstrap. Workloads have no public address, so each gets an
    C(ansible_ssh_common_args) carrying a C(ProxyCommand) through the
    bastion's discovered address, plus C(oilscope_bastion_address) and
    C(oilscope_bastion_ssh_port) as data.
  - A workload's C(ProxyCommand) needs the bastion's discovered address, which
    a per-host C(compose) expression cannot see, so these are applied in
    Python once the delegate has finished rather than composed per host.
  - Uses C(ec2_tags) (added in amazon.aws 11.2.0), not the deprecated C(tags)
    host variable, so tag-keyed groups and composed variables keep working
    after C(tags) is removed.
"""

EXAMPLES = r"""
# inventory/oilscope-aws.yml - the path comes from OILSCOPE_PROJECT_CONFIG or
# the option default, so it is deliberately not set here.
plugin: oilscope.platform.oilscope_aws
cache: true
cache_plugin: ansible.builtin.jsonfile
cache_connection: ~/.cache/oilscope-inventory-aws
cache_timeout: 300
"""

DELEGATE = "amazon.aws.aws_ec2"
display = Display()


class InventoryModule(BaseInventoryPlugin, Cacheable):
    NAME = "oilscope.platform.oilscope_aws"

    def verify_file(self, path):
        return super().verify_file(path) and path.endswith(("oilscope-aws.yml", "oilscope-aws.yaml"))

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache=cache)
        self._read_config_data(path)

        if not HAS_YAML:
            raise AnsibleParserError("the oilscope_aws inventory plugin requires PyYAML")

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

        validate_inventory_hosts(inventory, config, "AWS")
        apply_connection_vars(inventory, config, plain(self.get_option("bastion_role")), "AWS")

    def _build_settings(self, config):
        region_key = require_str(config, "region")
        name_prefix = require_str(config, "name_prefix")
        environment = require_str(config, "environment")
        region = require_str(config, "region_map", region_key, "aws", "region")

        bastion_role = plain(self.get_option("bastion_role"))
        bastion_port = compute_bastion_ssh_port(config, bastion_role)
        vm_key_pattern = vm_key_regex(name_prefix, environment)

        is_bastion = f"ec2_tags.role | default('') == '{bastion_role}'"
        public = "public_ip_address"
        private = "private_ip_address"

        return {
            "plugin": DELEGATE,
            "regions": [plain(region)],
            "filters": {
                "tag:application": plain(name_prefix),
                "tag:environment": plain(environment),
                "instance-state-name": "running",
            },
            "hostnames": ["tag:Name"],
            "keyed_groups": [{"key": "ec2_tags.role", "prefix": "", "separator": ""}],
            "groups": {"workloads": f"ec2_tags.role is defined and ec2_tags.role != '{bastion_role}'"},
            "compose": {
                "internal_ip": private,
                # default(..., true) rather than `public if public else ''`:
                # a private instance has no public_ip_address key at all, and
                # testing an undefined field's truthiness is exactly what
                # broke this for private instances - see the GCP plugin's
                # has_public, which sidesteps the same trap by testing a
                # field (accessConfigs) that's always present.
                "public_ip": f"{public} | default('', true)",
                "ansible_host": f"{public} if ({is_bastion}) else {private}",
                "bastion_ssh_port": str(bastion_port),
                "oilscope_role": "ec2_tags.role | default('')",
                "oilscope_cloud": "'aws'",
                "oilscope_vm_key": f"ec2_tags.Name | regex_replace('{vm_key_pattern}', '')",
            },
        }

    def _write_settings(self, settings):
        digest = hashlib.sha256(json.dumps(settings, sort_keys=True).encode("utf-8")).hexdigest()
        generated = os.path.join(tempfile.gettempdir(), f"oilscope-{digest[:16]}.aws.yml")

        try:
            with open(generated, "w") as handle:
                yaml.safe_dump(settings, handle, default_flow_style=False)
        except OSError as write_error:
            raise AnsibleParserError(
                f"could not write the generated aws_ec2 settings to {generated}: {write_error}"
            ) from write_error

        return generated

    def _delegate(self, inventory, loader, generated, cache):
        from ansible.plugins.loader import inventory_loader

        delegate = inventory_loader.get(DELEGATE)

        if delegate is None:
            raise AnsibleParserError(
                f"the {DELEGATE} inventory plugin is unavailable; "
                "install the amazon.aws collection"
            )

        for option in ("cache", "cache_plugin", "cache_connection", "cache_timeout"):
            try:
                delegate.set_option(option, self.get_option(option))
            except (AnsibleError, KeyError) as option_error:
                display.vvv(f"{DELEGATE} rejected the {option} option: {option_error}")

        delegate.parse(inventory, loader, generated, cache=cache)
