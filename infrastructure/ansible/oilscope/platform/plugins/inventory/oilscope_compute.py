# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Push and Pray team
"""Derive gcp_compute/aws_ec2 settings from the shared project configuration JSON."""

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
name: oilscope_compute
short_description: OilScope inventory derived from the project configuration
version_added: "0.1.0"
author:
  - Push and Pray team
description:
  - Derives GCP and AWS discovery settings from the project configuration JSON
    that Terraform also reads, then hands them to C(google.cloud.gcp_compute)
    and C(amazon.aws.aws_ec2), which perform the actual discovery. No
    environment value is repeated here.
  - Both clouds are always queried. Which resources actually turn up on each
    is decided by the C(cloud) label/tag Terraform stamps on every instance
    it creates - the plugin does not re-derive per-VM cloud placement from
    the config's C(cloud)/C(vms.*.cloud) override fields, since Terraform has
    already resolved that placement and stamped its answer on the resource.
    GCP discovery is skipped only when the configuration has no C(project_id)
    - AWS needs no equivalent identifier, since the credential chain already
    scopes it to one account.
  - The wrapper exists because neither delegate plugin reads this file, nor
    evaluates Jinja in its own configuration - a template expression there
    reaches the API as literal text.
extends_documentation_fragment:
  - inventory_cache
options:
  plugin:
    description:
      - Token that identifies this plugin. Must be
        C(oilscope.platform.oilscope_compute).
    type: str
    required: true
    choices:
      - oilscope.platform.oilscope_compute
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
  workload_ssh_port:
    description:
      - Port the workload VMs listen on. The Terraform firewall/security
        group rules open 22 and nothing else, so the bastion's port must not
        apply to them.
    type: int
    default: 22
  bastion_role:
    description:
      - Value of C(role) identifying the bastion, in the configuration and in
        the instance label/tag.
    type: str
    default: bastion
  auth_kind:
    description:
      - Passed straight through to C(gcp_compute). GCP-specific; AWS
        authenticates through the standard boto3 credential chain instead.
    type: str
    default: application
  gcp_vars_prefix:
    description:
      - Prefix for the raw instance fields C(gcp_compute) copies into host
        variables; without one its C(name) and C(tags) collide with reserved
        names.
    type: str
    default: gcp_
requirements:
  - google.cloud collection
  - amazon.aws collection
  - google-auth, requests (for gcp_compute)
  - boto3, botocore (for aws_ec2)
notes:
  - GCP authenticates with Application Default Credentials. Run
    C(gcloud auth application-default login) on the controller first.
  - AWS authenticates with the standard boto3 credential chain (environment
    variables, a named profile, or an attached role).
"""

EXAMPLES = r"""
# inventory/oilscope.yml - the path comes from OILSCOPE_PROJECT_CONFIG or the
# option default, so it is deliberately not set here.
plugin: oilscope.platform.oilscope_compute
cache: true
cache_plugin: ansible.builtin.jsonfile
cache_connection: ~/.cache/oilscope-inventory
cache_timeout: 300
"""

GCP_DELEGATE = "google.cloud.gcp_compute"
GCP_COLLECTION = "google.cloud"
AWS_DELEGATE = "amazon.aws.aws_ec2"
AWS_COLLECTION = "amazon.aws"
display = Display()


def plain(value):
    return str(value)


class InventoryModule(BaseInventoryPlugin, Cacheable):
    NAME = "oilscope.platform.oilscope_compute"

    def verify_file(self, path):
        return super().verify_file(path) and path.endswith(("oilscope.yml", "oilscope.yaml"))

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache=cache)
        self._read_config_data(path)

        if not HAS_YAML:
            raise AnsibleParserError("the oilscope_compute inventory plugin requires PyYAML")

        config = self._load_project_config(path)
        name_prefix = self._require(config, "name_prefix")
        environment = self._require(config, "environment")
        bastion_port = self._bastion_ssh_port(config)
        workload_port = int(self.get_option("workload_ssh_port"))
        gcp_zones, aws_regions = self._region_scopes(config)

        generated_files = []
        try:
            project_id = config.get("project_id")

            if project_id and gcp_zones:
                settings = self._gcp_settings(
                    project_id, gcp_zones, name_prefix, environment, bastion_port, workload_port
                )
                generated = self._write_settings(settings, "gcp")
                generated_files.append(generated)
                self._delegate(GCP_DELEGATE, GCP_COLLECTION, inventory, loader, generated, cache)
            else:
                display.vvv(
                    "skipping GCP discovery: the project configuration has no project_id"
                )

            if aws_regions:
                settings = self._aws_settings(
                    aws_regions, name_prefix, environment, bastion_port, workload_port
                )
                generated = self._write_settings(settings, "aws")
                generated_files.append(generated)
                self._delegate(AWS_DELEGATE, AWS_COLLECTION, inventory, loader, generated, cache)
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

    def _require(self, config, key):
        value = config.get(key)

        if not value or not isinstance(value, str):
            raise AnsibleParserError(
                f"the project configuration must define a non-empty string {key!r}"
            )

        return value

    def _region_scopes(self, config):
        regions = config.get("regions")

        if not isinstance(regions, dict) or not regions:
            raise AnsibleParserError(
                "the project configuration must define a non-empty 'regions' object"
            )

        gcp_zones = set()
        aws_regions = set()

        for label, entry in regions.items():
            if not isinstance(entry, dict):
                raise AnsibleParserError(
                    f"regions[{label!r}] must be an object with 'gcp' and 'aws' placements"
                )

            gcp_placement = entry.get("gcp")
            aws_placement = entry.get("aws")

            if isinstance(gcp_placement, dict) and gcp_placement.get("zone"):
                gcp_zones.add(plain(gcp_placement["zone"]))

            if isinstance(aws_placement, dict) and aws_placement.get("region"):
                aws_regions.add(plain(aws_placement["region"]))

        return sorted(gcp_zones), sorted(aws_regions)

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

    def _gcp_settings(self, project_id, zones, name_prefix, environment, bastion_port, workload_port):
        bastion_role = plain(self.get_option("bastion_role"))
        auth_kind = plain(self.get_option("auth_kind"))
        vars_prefix = plain(self.get_option("gcp_vars_prefix"))

        is_bastion = f"labels.role | default('') == '{bastion_role}'"
        has_public = "networkInterfaces[0].accessConfigs | default([])"
        public = "networkInterfaces[0].accessConfigs[0].natIP"
        private = "networkInterfaces[0].networkIP"

        return {
            "plugin": GCP_DELEGATE,
            "projects": [plain(project_id)],
            "zones": zones,
            "filters": [
                f"labels.application = {plain(name_prefix)}",
                f"labels.environment = {plain(environment)}",
                "labels.cloud = gcp",
            ],
            "auth_kind": auth_kind,
            "hostnames": ["name"],
            "vars_prefix": vars_prefix,
            "keyed_groups": [
                {"key": "labels.role", "prefix": "", "separator": ""},
                {"key": "labels.cloud", "prefix": "", "separator": ""},
            ],
            "groups": {"workloads": f"labels.role is defined and labels.role != '{bastion_role}'"},
            "compose": {
                "internal_ip": private,
                "public_ip": f"{public} if {has_public} else ''",
                "ansible_host": f"{public} if {is_bastion} else {private}",
                "ansible_port": f"{bastion_port} if {is_bastion} else {workload_port}",
                "oilscope_role": "labels.role | default('')",
                "oilscope_cloud": "labels.cloud | default('')",
            },
        }

    def _aws_settings(self, regions, name_prefix, environment, bastion_port, workload_port):
        bastion_role = plain(self.get_option("bastion_role"))

        is_bastion = f"tags.Role | default('') == '{bastion_role}'"

        return {
            "plugin": AWS_DELEGATE,
            "regions": regions,
            "filters": {
                "tag:Application": plain(name_prefix),
                "tag:Environment": plain(environment),
                "tag:Cloud": "aws",
                "instance-state-name": "running",
            },
            "hostnames": ["tag:Name"],
            "keyed_groups": [
                {"key": "tags.Role", "prefix": "", "separator": ""},
                {"key": "tags.Cloud", "prefix": "", "separator": ""},
            ],
            "groups": {"workloads": f"tags.Role is defined and tags.Role != '{bastion_role}'"},
            "compose": {
                "internal_ip": "private_ip_address",
                "public_ip": "public_ip_address | default('', true)",
                "ansible_host": f"public_ip_address if ({is_bastion}) else private_ip_address",
                "ansible_port": f"{bastion_port} if ({is_bastion}) else {workload_port}",
                "oilscope_role": "tags.Role | default('')",
                "oilscope_cloud": "tags.Cloud | default('')",
            },
        }

    def _write_settings(self, settings, suffix):
        digest = hashlib.sha256(json.dumps(settings, sort_keys=True).encode("utf-8")).hexdigest()
        generated = os.path.join(tempfile.gettempdir(), f"oilscope-{digest[:16]}.{suffix}.yml")

        try:
            with open(generated, "w") as handle:
                yaml.safe_dump(settings, handle, default_flow_style=False)
        except OSError as write_error:
            raise AnsibleParserError(
                f"could not write the generated {suffix} inventory settings to {generated}: {write_error}"
            ) from write_error

        return generated

    def _delegate(self, delegate_name, collection_hint, inventory, loader, generated, cache):
        from ansible.plugins.loader import inventory_loader

        delegate = inventory_loader.get(delegate_name)

        if delegate is None:
            raise AnsibleParserError(
                f"the {delegate_name} inventory plugin is unavailable; "
                f"install the {collection_hint} collection"
            )

        for option in ("cache", "cache_plugin", "cache_connection", "cache_timeout"):
            try:
                delegate.set_option(option, self.get_option(option))
            except (AnsibleError, KeyError) as option_error:
                display.vvv(f"{delegate_name} rejected the {option} option: {option_error}")

        delegate.parse(inventory, loader, generated, cache=cache)