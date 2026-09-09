# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Push and Pray team
"""Config-derivation helpers shared by every OilScope dynamic inventory plugin.

Both oilscope_gcp and oilscope_aws derive their delegate's settings from the
same project configuration JSON that Terraform reads. This module is the one
place that knows how to load that file, how to find the bastion's SSH port in
it, and how a VM's cloud resource name maps back to its key in `vms`- so the
two plugins cannot drift from each other on those points.
"""

import json
import os
import re

from ansible.errors import AnsibleParserError


def plain(value):
    return str(value)


def resolve_config_path(configured, inventory_file_path):
    """Resolve project_config_path the same way for every OilScope inventory plugin.

    Absolute is used as given. Relative is tried against the working
    directory first, then against the inventory file's own directory, so a
    path typed from the repository root works either way.
    """
    if os.path.isabs(configured):
        return os.path.normpath(configured)

    from_cwd = os.path.abspath(configured)

    if os.path.isfile(from_cwd):
        return from_cwd

    beside = os.path.join(os.path.dirname(os.path.abspath(inventory_file_path)), configured)
    return os.path.normpath(beside)


def load_project_config(config_path):
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


def require_str(config, *path):
    """Require a non-empty string at a nested path, e.g.

    require_str(config, "clouds", "gcp", "project_id").
    """
    value = config

    for key in path:
        if not isinstance(value, dict):
            value = None
            break

        value = value.get(key)

    if not value or not isinstance(value, str):
        dotted = ".".join(str(segment) for segment in path)
        raise AnsibleParserError(
            f"the project configuration must define a non-empty string at {dotted!r}"
        )

    return value


def bastion_ssh_port(config, bastion_role):
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


def vm_key_regex(name_prefix, environment):
    """Regex matching the '<name_prefix>-<environment>-' prefix every cloud
    puts in front of a VM's config key to form its resource name (Terraform:
    `${resource_prefix}-${key}`, resource_prefix = "<name_prefix>-<environment>").
    """
    prefix = f"{plain(name_prefix)}-{plain(environment)}-"
    return "^" + re.escape(prefix)


def effective_cloud(vm, config):
    """The cloud a VM actually deploys to: its own `cloud` override, or the
    configuration's `default_cloud`.
    """
    return vm.get("cloud", config.get("default_cloud"))


def vms_for_cloud(config, cloud_name):
    """The subset of `vms` that resolve to the given cloud."""
    vms = config.get("vms", {})
    cloud_key = plain(cloud_name).lower()

    return {
        key: vm
        for key, vm in vms.items()
        if isinstance(vm, dict) and effective_cloud(vm, config) == cloud_key
    }


def validate_inventory_hosts(inventory, config, cloud_name):
    """Fail loudly on any mismatch between the project configuration and what
    was actually discovered, instead of quietly producing a wrong or
    incomplete inventory that only surfaces as a confusing failure later - or
    as no failure at all, if a deployment play simply has nothing to run
    against and reports success.
    """
    cloud_key = plain(cloud_name).lower()
    expected = vms_for_cloud(config, cloud_name)
    found_keys = set()

    for host_name in list(inventory.hosts):
        host = inventory.get_host(host_name)
        host_vars = host.get_vars()
        vm_key = host_vars.get("oilscope_vm_key")

        if not vm_key or vm_key not in config.get("vms", {}):
            raise AnsibleParserError(
                f"discovered {cloud_name} host {host_name!r} does not map to any VM "
                f"in the project configuration (derived key: {vm_key!r}); check that "
                "name_prefix/environment match, and that the instance's Name/name "
                "field is exactly '<name_prefix>-<environment>-<vm key>'"
            )

        vm = config["vms"][vm_key]
        found_keys.add(vm_key)

        expected_role = vm.get("role")
        actual_role = host_vars.get("oilscope_role")

        if expected_role != actual_role:
            raise AnsibleParserError(
                f"discovered {cloud_name} host {host_name!r} (config key {vm_key!r}) "
                f"has role {actual_role!r}, but the project configuration says "
                f"{expected_role!r}; the instance's role tag/label is out of sync "
                "with the configuration"
            )

        vm_cloud = effective_cloud(vm, config)

        if vm_cloud != cloud_key:
            raise AnsibleParserError(
                f"discovered {cloud_name} host {host_name!r} (config key {vm_key!r}) "
                f"is configured for cloud {vm_cloud!r}, not {cloud_key!r}; the "
                "project configuration and the cloud actually queried have "
                "drifted apart - check for a stale/orphaned instance, or a "
                "recent 'cloud'/'default_cloud' change"
            )

    missing = sorted(set(expected) - found_keys)

    if missing:
        raise AnsibleParserError(
            f"{cloud_name} inventory is missing VMs the project configuration "
            f"expects on {cloud_key}: {', '.join(missing)}. An empty or "
            "partial discovery must not be mistaken for 'nothing exists yet' - "
            "check the region and application/environment filters actually "
            "match reality, and that terraform apply has run."
        )
