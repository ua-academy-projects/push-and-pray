# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Push and Pray team

"""Build OilScope inventory dynamically across configured cloud providers."""

import hashlib
import json
import os
import tempfile

from ansible.errors import AnsibleError, AnsibleParserError
from ansible.plugins.inventory import BaseInventoryPlugin, Cacheable
from ansible.plugins.loader import inventory_loader
from ansible.utils.display import Display

try:
    import yaml

    HAS_YAML = True
except ImportError:  # pragma: no cover
    HAS_YAML = False


DOCUMENTATION = r"""
name: oilscope
short_description: OilScope multi-cloud dynamic inventory
version_added: "0.1.0"
author:
  - Push and Pray team
description:
  - Reads the same project configuration JSON used by Terraform.
  - Determines which cloud providers are used by configured VMs.
  - Discovers GCP Compute Engine instances through google.cloud.gcp_compute.
  - Discovers AWS EC2 instances through amazon.aws.aws_ec2.
  - Applies common OilScope role groups and connection variables.
extends_documentation_fragment:
  - inventory_cache
options:
  plugin:
    description:
      - Token identifying this inventory plugin.
    type: str
    required: true
    choices:
      - oilscope.platform.oilscope
  project_config_path:
    description:
      - Path to the shared project configuration JSON.
      - OILSCOPE_PROJECT_CONFIG may override the default path.
    type: str
    required: false
    default: ../../../project-config.example.json
    env:
      - name: OILSCOPE_PROJECT_CONFIG
  workload_ssh_port:
    description:
      - SSH port used by non-bastion workload VMs.
    type: int
    default: 22
  bastion_role:
    description:
      - Provider-neutral role identifying the bastion.
    type: str
    default: bastion
requirements:
  - google.cloud collection for GCP discovery
  - amazon.aws collection for AWS discovery
  - google-auth
  - boto3
  - botocore
notes:
  - GCP discovery uses Application Default Credentials.
  - AWS discovery uses the standard boto3 credential chain.
"""


EXAMPLES = r"""
# inventory/oilscope.yml
plugin: oilscope.platform.oilscope
cache: false
"""


GCP_DELEGATE = "google.cloud.gcp_compute"
AWS_DELEGATE = "amazon.aws.aws_ec2"

display = Display()


def plain(value):
    return str(value)


class InventoryModule(BaseInventoryPlugin, Cacheable):
    NAME = "oilscope.platform.oilscope"

    def verify_file(self, path):
        return super().verify_file(path) and path.endswith(
            ("oilscope.yml", "oilscope.yaml")
        )

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache=cache)
        self._read_config_data(path)

        if not HAS_YAML:
            raise AnsibleParserError(
                "the oilscope inventory plugin requires PyYAML"
            )

        config = self._load_project_config(path)
        providers = self._configured_providers(config)

        if "gcp" in providers:
            settings = self._build_gcp_settings(config)
            generated = self._write_settings(
                settings,
                suffix="gcp_compute.yml",
            )

            try:
                self._delegate(
                    GCP_DELEGATE,
                    inventory,
                    loader,
                    generated,
                    cache,
                )
            finally:
                self._cleanup(generated)

        if "aws" in providers:
            settings = self._build_aws_settings(config)
            generated = self._write_settings(
                settings,
                suffix="aws_ec2.yml",
            )

            try:
                self._delegate(
                    AWS_DELEGATE,
                    inventory,
                    loader,
                    generated,
                    cache,
                )
            finally:
                self._cleanup(generated)

    def _resolve_config_path(self, inventory_path):
        configured = os.environ.get(
            "OILSCOPE_PROJECT_CONFIG",
            self.get_option("project_config_path"),
        )

        configured = plain(configured)

        if os.path.isabs(configured):
            return os.path.normpath(configured)

        from_cwd = os.path.abspath(configured)

        if os.path.isfile(from_cwd):
            return from_cwd

        beside_inventory = os.path.join(
            os.path.dirname(os.path.abspath(inventory_path)),
            configured,
        )

        return os.path.normpath(beside_inventory)

    def _load_project_config(self, inventory_path):
        config_path = self._resolve_config_path(inventory_path)

        try:
            with open(config_path, "r", encoding="utf-8") as handle:
                config = json.load(handle)
        except (OSError, ValueError) as error:
            raise AnsibleParserError(
                "could not load the project configuration at "
                f"{config_path}: {error}"
            ) from error

        if not isinstance(config, dict):
            raise AnsibleParserError(
                "the project configuration must contain a JSON object"
            )

        return config

    def _require_string(self, mapping, key, context):
        value = mapping.get(key)

        if not isinstance(value, str) or not value:
            raise AnsibleParserError(
                f"{context} must define a non-empty string {key!r}"
            )

        return value

    def _vms(self, config):
        vms = config.get("vms")

        if not isinstance(vms, dict) or not vms:
            raise AnsibleParserError(
                "the project configuration must define a non-empty 'vms' object"
            )

        return vms

    def _default_cloud(self, config):
        value = self._require_string(
            config,
            "default_cloud",
            "project configuration",
        )

        if value not in {"gcp", "aws"}:
            raise AnsibleParserError(
                "default_cloud must be either 'gcp' or 'aws'"
            )

        return value

    def _default_region(self, config):
        return self._require_string(
            config,
            "default_region",
            "project configuration",
        )

    def _vm_cloud(self, vm, default_cloud):
        cloud = vm.get("cloud", default_cloud)

        if cloud not in {"gcp", "aws"}:
            raise AnsibleParserError(
                f"unsupported VM cloud {cloud!r}"
            )

        return cloud

    def _vm_region(self, vm, default_region):
        region = vm.get("region", default_region)

        if not isinstance(region, str) or not region:
            raise AnsibleParserError(
                "VM region must be a non-empty logical region name"
            )

        return region

    def _configured_providers(self, config):
        default_cloud = self._default_cloud(config)

        providers = {
            self._vm_cloud(vm, default_cloud)
            for vm in self._vms(config).values()
            if isinstance(vm, dict)
        }

        return providers

    def _cloud_mappings(self, config):
        mappings = config.get("cloud_mappings")

        if not isinstance(mappings, dict):
            raise AnsibleParserError(
                "the project configuration must define 'cloud_mappings'"
            )

        return mappings

    def _provider_regions(self, config, provider):
        mappings = self._cloud_mappings(config)
        regions = mappings.get("regions")

        if not isinstance(regions, dict):
            raise AnsibleParserError(
                "cloud_mappings must define a 'regions' object"
            )

        default_cloud = self._default_cloud(config)
        default_region = self._default_region(config)

        logical_regions = {
            self._vm_region(vm, default_region)
            for vm in self._vms(config).values()
            if (
                isinstance(vm, dict)
                and self._vm_cloud(vm, default_cloud) == provider
            )
        }

        resolved_regions = []

        for logical_region in sorted(logical_regions):
            logical_mapping = regions.get(logical_region)

            if not isinstance(logical_mapping, dict):
                raise AnsibleParserError(
                    f"no cloud mapping exists for region {logical_region!r}"
                )

            provider_mapping = logical_mapping.get(provider)

            if not isinstance(provider_mapping, dict):
                raise AnsibleParserError(
                    f"region {logical_region!r} has no {provider!r} mapping"
                )

            provider_region = self._require_string(
                provider_mapping,
                "region",
                f"{provider} region mapping {logical_region!r}",
            )

            if provider_region not in resolved_regions:
                resolved_regions.append(provider_region)

        return resolved_regions

    def _provider_zones(self, config, provider):
        mappings = self._cloud_mappings(config)
        regions = mappings.get("regions")

        if not isinstance(regions, dict):
            raise AnsibleParserError(
                "cloud_mappings must define a 'regions' object"
            )

        default_cloud = self._default_cloud(config)
        default_region = self._default_region(config)

        logical_regions = {
            self._vm_region(vm, default_region)
            for vm in self._vms(config).values()
            if (
                isinstance(vm, dict)
                and self._vm_cloud(vm, default_cloud) == provider
            )
        }

        resolved_zones = []

        for logical_region in sorted(logical_regions):
            logical_mapping = regions.get(logical_region)

            if not isinstance(logical_mapping, dict):
                raise AnsibleParserError(
                    f"no cloud mapping exists for region {logical_region!r}"
                )

            provider_mapping = logical_mapping.get(provider)

            if not isinstance(provider_mapping, dict):
                raise AnsibleParserError(
                    f"region {logical_region!r} has no {provider!r} mapping"
                )

            provider_zone = self._require_string(
                provider_mapping,
                "zone",
                f"{provider} region mapping {logical_region!r}",
            )

            if provider_zone not in resolved_zones:
                resolved_zones.append(provider_zone)

        return resolved_zones

    def _single_provider_region(self, config, provider):
        regions = self._provider_regions(config, provider)

        if len(regions) != 1:
            raise AnsibleParserError(
                f"the current {provider} architecture requires exactly one "
                f"resolved provider region, found {len(regions)}"
            )

        return regions[0]

    def _bastion_ssh_port(self, config):
        bastion_role = plain(self.get_option("bastion_role"))

        bastions = [
            vm
            for vm in self._vms(config).values()
            if (
                isinstance(vm, dict)
                and vm.get("role") == bastion_role
            )
        ]

        if len(bastions) != 1:
            raise AnsibleParserError(
                "expected exactly one VM with role "
                f"{bastion_role!r}, found {len(bastions)}"
            )

        try:
            return int(bastions[0]["ssh_port"])
        except (KeyError, TypeError, ValueError) as error:
            raise AnsibleParserError(
                f"the {bastion_role!r} VM must define an integer ssh_port"
            ) from error

    def _build_gcp_settings(self, config):
        clouds = config.get("clouds")

        if not isinstance(clouds, dict):
            raise AnsibleParserError(
                "the project configuration must define 'clouds'"
            )

        gcp = clouds.get("gcp")

        if not isinstance(gcp, dict):
            raise AnsibleParserError(
                "the project configuration must define clouds.gcp"
            )

        project_id = self._require_string(
            gcp,
            "project_id",
            "clouds.gcp",
        )

        name_prefix = self._require_string(
            config,
            "name_prefix",
            "project configuration",
        )

        environment = self._require_string(
            config,
            "environment",
            "project configuration",
        )

        zones = self._provider_zones(config, "gcp")
        provider_region = self._single_provider_region(config, "gcp")

        bastion_role = plain(self.get_option("bastion_role"))
        bastion_port = self._bastion_ssh_port(config)
        workload_port = int(self.get_option("workload_ssh_port"))

        is_bastion = (
            f"labels.role | default('') == '{bastion_role}'"
        )

        has_public = (
            "networkInterfaces[0].accessConfigs | default([])"
        )

        public_ip = (
            "networkInterfaces[0].accessConfigs[0].natIP"
        )

        private_ip = "networkInterfaces[0].networkIP"

        return {
            "plugin": GCP_DELEGATE,
            "projects": [plain(project_id)],
            "zones": zones,
            "filters": [
                f"labels.application = {plain(name_prefix)}",
                f"labels.environment = {plain(environment)}",
                "labels.cloud = gcp",
            ],
            "auth_kind": "application",
            "hostnames": ["name"],
            "vars_prefix": "gcp_",
            "keyed_groups": [
                {
                    "key": "labels.role",
                    "prefix": "",
                    "separator": "",
                },
            ],
            "groups": {
                "workloads": (
                    "labels.role is defined and "
                    f"labels.role != '{bastion_role}'"
                ),
                "gcp": "true",
            },
            "compose": {
                "internal_ip": private_ip,
                "public_ip": (
                    f"{public_ip} if {has_public} else ''"
                ),
                "ansible_host": (
                    f"{public_ip} if {is_bastion} "
                    f"else {private_ip}"
                ),
                "ansible_port": (
                    f"{bastion_port} if {is_bastion} "
                    f"else {workload_port}"
                ),
                "oilscope_role": (
                    "labels.role | default('')"
                ),
                "oilscope_cloud": "'gcp'",
                "oilscope_region": repr(provider_region),
            },
        }

    def _build_aws_settings(self, config):
        name_prefix = self._require_string(
            config,
            "name_prefix",
            "project configuration",
        )

        environment = self._require_string(
            config,
            "environment",
            "project configuration",
        )

        provider_region = self._single_provider_region(config, "aws")

        bastion_role = plain(self.get_option("bastion_role"))
        bastion_port = self._bastion_ssh_port(config)
        workload_port = int(self.get_option("workload_ssh_port"))

        return {
            "plugin": AWS_DELEGATE,
            "regions": [provider_region],
            "filters": {
                "tag:application": name_prefix,
                "tag:environment": environment,
                "tag:cloud": "aws",
                "instance-state-name": "running",
            },
            "hostnames": [
                "tag:Name",
            ],
            "hostvars_prefix": "aws_",
            "keyed_groups": [
                {
                    "key": "tags.role",
                    "prefix": "",
                    "separator": "",
                },
            ],
            "groups": {
                "workloads": (
                    "tags.role is defined and "
                    f"tags.role != '{bastion_role}'"
                ),
                "aws": "true",
            },
            "compose": {
                "internal_ip": "private_ip_address",
                "public_ip": "public_ip_address | default('')",
                "ansible_host": (
                    "public_ip_address "
                    f"if tags.role == '{bastion_role}' "
                    "else private_ip_address"
                ),
                "ansible_port": (
                    f"{bastion_port} "
                    f"if tags.role == '{bastion_role}' "
                    f"else {workload_port}"
                ),
                "oilscope_role": "tags.role | default('')",
                "oilscope_cloud": "'aws'",
                "oilscope_region": repr(provider_region),
            },
        }

    def _write_settings(self, settings, suffix):
        digest = hashlib.sha256(
            json.dumps(
                settings,
                sort_keys=True,
            ).encode("utf-8")
        ).hexdigest()

        generated = os.path.join(
            tempfile.gettempdir(),
            f"oilscope-{digest[:16]}.{suffix}",
        )

        try:
            with open(
                generated,
                "w",
                encoding="utf-8",
            ) as handle:
                yaml.safe_dump(
                    settings,
                    handle,
                    default_flow_style=False,
                )
        except OSError as error:
            raise AnsibleParserError(
                "could not write generated inventory settings "
                f"to {generated}: {error}"
            ) from error

        return generated

    def _cleanup(self, path):
        try:
            os.unlink(path)
        except OSError as error:
            display.vvv(
                f"could not remove temporary inventory file "
                f"{path}: {error}"
            )

    def _delegate(
        self,
        delegate_name,
        inventory,
        loader,
        generated,
        cache,
    ):
        delegate = inventory_loader.get(delegate_name)

        if delegate is None:
            raise AnsibleParserError(
                f"the {delegate_name} inventory plugin is unavailable"
            )

        for option in (
            "cache",
            "cache_plugin",
            "cache_connection",
            "cache_timeout",
        ):
            try:
                delegate.set_option(
                    option,
                    self.get_option(option),
                )
            except (AnsibleError, KeyError) as error:
                display.vvv(
                    f"{delegate_name} rejected "
                    f"the {option} option: {error}"
                )

        delegate.parse(
            inventory,
            loader,
            generated,
            cache=cache,
        )
