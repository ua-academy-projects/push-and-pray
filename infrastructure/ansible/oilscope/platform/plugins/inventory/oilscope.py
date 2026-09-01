# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Push and Pray team
"""Derive cloud inventory settings from the shared project configuration JSON."""

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
name: oilscope
short_description: OilScope inventory derived from the project configuration
version_added: "0.1.0"
author:
  - Push and Pray team
description:
  - Derives the C(application) and C(environment) filters, the bastion SSH port
    and the per-cloud coordinates from the project configuration JSON that
    Terraform also reads, then hands them to the upstream discovery plugin of
    every cloud the configuration targets - C(google.cloud.gcp_compute) for
    C(gcp) and C(amazon.aws.aws_ec2) for C(aws). No environment value is
    repeated here.
  - The clouds come from C(default_cloud) and the optional per-VM C(cloud) key,
    so a configuration that names one cloud reaches one provider and a mixed one
    reaches both into a single inventory.
  - The wrapper exists because neither upstream plugin reads that file nor
    evaluates Jinja in its own configuration - a template expression there
    reaches the API as literal text.
extends_documentation_fragment:
  - inventory_cache
options:
  plugin:
    description:
      - Token that identifies this plugin. Must be C(oilscope.platform.oilscope).
    type: str
    required: true
    choices:
      - oilscope.platform.oilscope
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
        the instance label or tag.
    type: str
    default: bastion
  auth_kind:
    description:
      - Passed straight through to C(gcp_compute).
    type: str
    default: application
  vars_prefix:
    description:
      - Prefix for the raw instance fields the upstream plugins copy into host
        variables; without one C(name) and C(tags) collide with names Ansible
        reserves.
    type: str
    default: gcp_
  aws_vars_prefix:
    description:
      - The same, for C(aws_ec2), which spells the option C(hostvars_prefix).
    type: str
    default: aws_
requirements:
  - google.cloud collection, google-auth and requests for gcp
  - amazon.aws collection and botocore for aws
notes:
  - C(ansible_port) is deliberately not composed here. Host variables from an
    inventory plugin outrank the C(group_vars) of the same inventory, and the
    bastion's bootstrap port override lives there.
  - GCP authenticates with Application Default Credentials. Run
    C(gcloud auth application-default login) on the controller first.
  - AWS authenticates with the standard credential chain, so an environment,
    profile or instance role already usable by the AWS CLI is enough.
  - The GCP search is not narrowed to a zone. The portable configuration names
    a location token rather than a zone, and the label filters already scope the
    result to one deployment.
"""

EXAMPLES = r"""
# inventory/oilscope.yml - the path comes from OILSCOPE_PROJECT_CONFIG or the
# option default, so it is deliberately not set here.
plugin: oilscope.platform.oilscope
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
    NAME = "oilscope.platform.oilscope"

    def verify_file(self, path):
        return super().verify_file(path) and path.endswith(("oilscope.yml", "oilscope.yaml"))

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache=cache)
        self._read_config_data(path)

        if not HAS_YAML:
            raise AnsibleParserError("the oilscope inventory plugin requires PyYAML")

        config = self._load_project_config(path)
        builders = {"gcp": self._gcp_settings, "aws": self._aws_settings}
        generated = {}

        try:
            for cloud in self._clouds(config):
                if cloud not in builders:
                    raise AnsibleParserError(
                        f"the project configuration targets the unsupported cloud {cloud!r}; "
                        f"supported: {', '.join(sorted(builders))}"
                    )

                settings = builders[cloud](config)
                generated[cloud] = self._write_settings(cloud, settings)

            for cloud, settings_path in generated.items():
                self._delegate(DELEGATES[cloud], inventory, loader, settings_path, cache)
        finally:
            for settings_path in generated.values():
                try:
                    os.unlink(settings_path)
                except OSError as cleanup_error:
                    display.vvv(f"could not remove {settings_path}: {cleanup_error}")

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

    def _vms(self, config):
        vms = config.get("vms")

        if not isinstance(vms, dict):
            raise AnsibleParserError("the project configuration must define a 'vms' object")

        return vms

    def _clouds(self, config):
        default_cloud = config.get("default_cloud")
        clouds = []

        for name, vm in self._vms(config).items():
            cloud = vm.get("cloud", default_cloud) if isinstance(vm, dict) else default_cloud

            if not cloud or not isinstance(cloud, str):
                raise AnsibleParserError(
                    f"the vm {name!r} names no cloud and the configuration defines no "
                    "non-empty string 'default_cloud'"
                )

            if cloud not in clouds:
                clouds.append(cloud)

        return sorted(clouds)

    def _require(self, config, *keys):
        value = config
        seen = []

        for key in keys:
            seen.append(key)

            if not isinstance(value, dict) or key not in value:
                raise AnsibleParserError(
                    f"the project configuration must define {'.'.join(seen)}"
                )

            value = value[key]

        if not value or not isinstance(value, str):
            raise AnsibleParserError(
                f"the project configuration must define a non-empty string {'.'.join(seen)!r}"
            )

        return value

    def _gcp_settings(self, config):
        project_id = self._require(config, "gcp", "project_id")
        name_prefix = self._require(config, "name_prefix")
        environment = self._require(config, "environment")

        bastion_role = plain(self.get_option("bastion_role"))

        is_bastion = f"labels.role | default('') == '{bastion_role}'"
        has_public = "networkInterfaces[0].accessConfigs | default([])"
        public = "networkInterfaces[0].accessConfigs[0].natIP"
        private = "networkInterfaces[0].networkIP"

        return {
            "plugin": DELEGATES["gcp"],
            "projects": [plain(project_id)],
            "filters": [
                f"labels.application = {plain(name_prefix)}",
                f"labels.environment = {plain(environment)}",
            ],
            "auth_kind": plain(self.get_option("auth_kind")),
            "hostnames": ["name"],
            "vars_prefix": plain(self.get_option("vars_prefix")),
            "keyed_groups": [{"key": "labels.role", "prefix": "", "separator": ""}],
            "groups": {
                "cloud_gcp": "true",
                "workloads": f"labels.role is defined and labels.role != '{bastion_role}'",
            },
            "compose": {
                "internal_ip": private,
                "public_ip": f"{public} if {has_public} else ''",
                "ansible_host": f"{public} if {is_bastion} else {private}",
                "oilscope_role": "labels.role | default('')",
                "oilscope_cloud": "'gcp'",
            },
        }

    def _aws_settings(self, config):
        name_prefix = self._require(config, "name_prefix")
        environment = self._require(config, "environment")
        regions = config.get("aws", {}).get("regions")

        if not isinstance(regions, list) or not regions:
            raise AnsibleParserError(
                "the project configuration must define a non-empty aws.regions list; "
                "aws_ec2 searches only the regions it is given"
            )

        bastion_role = plain(self.get_option("bastion_role"))
        prefix = plain(self.get_option("aws_vars_prefix"))

        tags = f"{prefix}tags | default(ec2_tags | default(tags, true), true)"
        role = f"({tags}).role | default('')"

        is_bastion = f"{role} == '{bastion_role}'"
        public = f"{prefix}public_ip_address | default(public_ip_address, true) | default('', true)"
        private = f"{prefix}private_ip_address | default(private_ip_address, true)"

        return {
            "plugin": DELEGATES["aws"],
            "regions": [plain(region) for region in regions],
            "filters": {
                "tag:application": plain(name_prefix),
                "tag:environment": plain(environment),
                "instance-state-name": ["running"],
            },
            "hostnames": ["tag:Name"],
            "hostvars_prefix": prefix,
            "strict": True,
            "keyed_groups": [{"key": role, "prefix": "", "separator": ""}],
            "groups": {
                "cloud_aws": "true",
                "workloads": f"{role} not in ['', '{bastion_role}']",
            },
            "compose": {
                "internal_ip": private,
                "public_ip": public,
                "ansible_host": f"({public}) if {is_bastion} else ({private})",
                "oilscope_role": role,
                "oilscope_cloud": "'aws'",
            },
        }

    def _write_settings(self, cloud, settings):
        digest = hashlib.sha256(json.dumps(settings, sort_keys=True).encode("utf-8")).hexdigest()
        suffix = "gcp.yml" if cloud == "gcp" else "aws_ec2.yml"
        generated = os.path.join(tempfile.gettempdir(), f"oilscope-{digest[:16]}.{suffix}")

        try:
            with open(generated, "w") as handle:
                yaml.safe_dump(settings, handle, default_flow_style=False)
        except OSError as write_error:
            raise AnsibleParserError(
                f"could not write the generated {settings['plugin']} settings to "
                f"{generated}: {write_error}"
            ) from write_error

        return generated

    def _delegate(self, name, inventory, loader, generated, cache):
        from ansible.plugins.loader import inventory_loader

        delegate = inventory_loader.get(name)

        if delegate is None:
            raise AnsibleParserError(
                f"the {name} inventory plugin is unavailable; "
                f"install the {name.rsplit('.', 1)[0]} collection"
            )

        for option in ("cache", "cache_plugin", "cache_connection", "cache_timeout"):
            try:
                delegate.set_option(option, self.get_option(option))
            except (AnsibleError, KeyError) as option_error:
                display.vvv(f"{name} rejected the {option} option: {option_error}")

        delegate.parse(inventory, loader, generated, cache=cache)
