# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Push and Pray team
"""Config-derivation helpers shared by every OilScope dynamic inventory plugin.

Both oilscope_gcp and oilscope_aws derive their delegate's settings from the
same project configuration JSON that Terraform reads. This module is the one
place that knows how to load that file, how to find the bastion's SSH port in
it, and how a VM's cloud resource name maps back to its key in `vms`- so the
two plugins cannot drift from each other on those points.

It also owns how the operator reaches those hosts: the SSH identity every
host is contacted with, the port the bastion itself answers on, and the
ProxyCommand that carries a workload connection through the bastion. Those
settings are applied here, in Python, once the delegate has discovered the
hosts - see `apply_connection_vars`.
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


# Applied to the bastion hop and to every direct connection alike:
# accept-new keeps first contact with a freshly created VM from prompting,
# and IdentitiesOnly stops ssh-agent from offering unrelated keys first and
# tripping the server's MaxAuthTries before the intended key is ever tried.
SSH_BASE_ARGS = "-o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes"


def ssh_user():
    """The operator's SSH user: OILSCOPE_SSH_USER, else the controller's own login."""
    return os.environ.get("OILSCOPE_SSH_USER") or os.environ.get("USER") or ""


def ssh_private_key_file():
    """The operator's SSH key: OILSCOPE_SSH_KEY, else the gcloud-managed key.

    The gcloud-managed key is a reasonable default only on GCP - an AWS
    operator's key is never provisioned there, so OILSCOPE_SSH_KEY is
    effectively required on AWS.
    """
    configured = os.environ.get("OILSCOPE_SSH_KEY")

    if configured:
        return configured

    return os.path.join(os.environ.get("HOME", ""), ".ssh", "google_compute_engine")


def bastion_connect_port(configured_port):
    """The port Ansible dials on the bastion itself.

    Defaults to the `ssh_port` in the project configuration, which is where
    sshd ends up. OILSCOPE_BASTION_CONNECT_PORT overrides it for first-boot
    bootstrap, when sshd is still on the image's default port and the
    configured one is not listening yet.
    """
    override = os.environ.get("OILSCOPE_BASTION_CONNECT_PORT")

    if not override:
        return configured_port

    try:
        return int(override)
    except (TypeError, ValueError) as port_error:
        raise AnsibleParserError(
            f"OILSCOPE_BASTION_CONNECT_PORT must be an integer port, got {override!r}"
        ) from port_error


def _proxy_command_args(user, key_file, bastion_address, bastion_hop_port):
    """ssh arguments that carry a workload connection through the bastion.

    The workload has no public address, so every connection to it is opened
    from the bastion with -W. The hop reuses the operator's own key and the
    same hardening flags as the outer connection.
    """
    proxy = (
        f"ssh -W %h:%p -q -p {bastion_hop_port} -i {key_file} "
        f"{SSH_BASE_ARGS} {user}@{bastion_address}"
    )
    return f'{SSH_BASE_ARGS} -o ProxyCommand="{proxy}"'


def apply_connection_vars(inventory, config, bastion_role, cloud_name):
    """Give every discovered host the SSH settings needed to reach it.

    Set here rather than in inventory `compose` because the workloads'
    ProxyCommand needs the bastion's discovered address, which only exists
    once the delegate has finished - a per-host compose expression cannot see
    another host. Set here rather than in `group_vars/` because that spreads
    one connection contract across three files whose names have to match
    group names the plugin itself invents.
    """
    user = ssh_user()
    key_file = ssh_private_key_file()
    hop_port = bastion_ssh_port(config, bastion_role)
    bastion_name = None
    workload_names = []

    for host_name in list(inventory.hosts):
        host_vars = inventory.get_host(host_name).get_vars()

        if host_vars.get("oilscope_role") == bastion_role:
            bastion_name = host_name
        else:
            workload_names.append(host_name)

        inventory.set_variable(host_name, "ansible_user", user)
        inventory.set_variable(host_name, "ansible_ssh_private_key_file", key_file)
        inventory.set_variable(host_name, "oilscope_ssh_base_args", SSH_BASE_ARGS)
        inventory.set_variable(host_name, "ansible_ssh_common_args", SSH_BASE_ARGS)

    if bastion_name is not None:
        inventory.set_variable(bastion_name, "ansible_port", bastion_connect_port(hop_port))

    if not workload_names:
        return

    if bastion_name is None:
        raise AnsibleParserError(
            f"the {cloud_name} inventory has workload hosts "
            f"({', '.join(sorted(workload_names))}) but no host with role "
            f"{bastion_role!r}. Workloads have no public address and are only "
            "reachable through the bastion, so they cannot be contacted from "
            "an inventory the bastion is absent from - check that the bastion "
            "VM resolves to this cloud and is running."
        )

    bastion_address = inventory.get_host(bastion_name).get_vars().get("ansible_host")

    if not bastion_address:
        raise AnsibleParserError(
            f"the discovered {cloud_name} bastion {bastion_name!r} has no address to "
            "proxy workload connections through; it needs a reachable public IP"
        )

    for host_name in workload_names:
        inventory.set_variable(host_name, "oilscope_bastion_address", bastion_address)
        inventory.set_variable(host_name, "oilscope_bastion_ssh_port", hop_port)
        inventory.set_variable(
            host_name,
            "ansible_ssh_common_args",
            _proxy_command_args(user, key_file, bastion_address, hop_port),
        )
