# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Four-VM dev environment for SkyIvano: one VM per component (postgres,
# backend-service, fetcher-service, ui-service), run under the QEMU provider
# (vagrant-qemu plugin) since this host is Apple Silicon and VirtualBox's
# arm64 support is not reliable enough to import boxes on it.
#
# Networking: every VM is bridged onto the same physical LAN as the host
# Mac and every other device on that network (QEMU's native vmnet-bridged
# backend, over en0), each with a fixed IP, and that bridged IP is the
# *only* way in - there is no NAT/forwarded-port fallback to localhost:
#
#   postgres  192.168.0.220  (port 5432)
#   backend   192.168.0.221  (port 8000)
#   fetcher   192.168.0.222  (port 8002)
#   ui        192.168.0.223  (port 5173)
#
# Cross-VM calls use these fixed LAN IPs directly - no slirp/NAT gateway
# trick needed. Because they're real LAN addresses, any other device on
# the same home network (phone, another laptop, ...) can reach them too,
# e.g. http://192.168.0.223:5173 for the UI - and so can this Mac, at the
# same address (not localhost:5173).
#
# Each VM still gets a second, user-mode NIC purely because the vagrant-qemu
# plugin requires one for its own SSH/provisioning control channel
# (`qe.ssh_port` below) - that NIC has no forwarded_port entries for any
# application port, so it exposes nothing but SSH.
#
# vmnet-bridged requires root: run `sudo vagrant up` (and `sudo vagrant
# reload` / `halt` / `destroy`) - the plugin warns if you don't, and a
# later unprivileged command can fail with EACCES on root-owned files (see
# the plugin's README "Known issue" section if that happens).
#
# The static IPs below sit at the high end of a typical home /24, above
# most routers' default DHCP pools, to avoid colliding with real devices -
# double check against your own router's DHCP range/reservations before
# relying on this. Adjust NETWORK_IPS/VMNET_INTERFACE if your LAN isn't
# 192.168.0.0/24 over en0.
#
# `vagrant up` brings machines up in the order defined below, matching
# this dependency chain (postgres -> backend -> fetcher -> ui): backend
# needs postgres to exist, fetcher's startup freshness check and every
# sync push need backend reachable, and ui's readiness check waits on
# backend.
#
# Synced folders use rsync (one-directional, host -> guest) rather than SMB:
# SMB synced folders need a manual "File Sharing" toggle in macOS System
# Settings plus a password prompt, which isn't worth the friction here. rsync
# pushes on `vagrant up`/`vagrant reload`/`vagrant provision`; for live sync
# while editing, run `vagrant rsync-auto` in another terminal.

BOX = "perk/ubuntu-2204-arm64"
VMNET_INTERFACE = "en0"

NETWORK_IPS = {
  postgres: "192.168.0.220",
  backend:  "192.168.0.221",
  fetcher:  "192.168.0.222",
  ui:       "192.168.0.223",
}

# node_modules/.venv are guest-built (Linux/arm64) - never rsync them from
# the host (macOS/arm64 has OS-specific native bindings that won't run in
# the guest), so the guest's own npm install / venv survives every re-sync.
RSYNC_EXCLUDES = ["node_modules", ".venv", "__pycache__", ".pytest_cache", ".git"]

Vagrant.configure("2") do |config|
  config.vm.define "postgres" do |node|
    node.vm.box = BOX
    node.vm.hostname = "skyivano-postgres"
    node.vm.network "private_network", ip: NETWORK_IPS[:postgres]

    node.vm.provider "qemu" do |qe|
      qe.ssh_port = 50110
      qe.memory = "512M"
      qe.smp = "1"
      qe.advanced_network = true
      qe.net_mode = :vmnet_bridged
      qe.vmnet_interface = VMNET_INTERFACE
    end

    node.vm.provision "shell", path: "vagrant/postgres/provision.sh"
  end

  config.vm.define "backend" do |node|
    node.vm.box = BOX
    node.vm.hostname = "skyivano-backend"
    node.vm.network "private_network", ip: NETWORK_IPS[:backend]

    node.vm.provider "qemu" do |qe|
      qe.ssh_port = 50111
      qe.memory = "768M"
      qe.smp = "1"
      qe.advanced_network = true
      qe.net_mode = :vmnet_bridged
      qe.vmnet_interface = VMNET_INTERFACE
    end

    node.vm.synced_folder "backend-service", "/app", type: "rsync", rsync__exclude: RSYNC_EXCLUDES
    node.vm.provision "shell", path: "vagrant/backend/provision.sh"
  end

  config.vm.define "fetcher" do |node|
    node.vm.box = BOX
    node.vm.hostname = "skyivano-fetcher"
    node.vm.network "private_network", ip: NETWORK_IPS[:fetcher]

    node.vm.provider "qemu" do |qe|
      qe.ssh_port = 50112
      qe.memory = "768M"
      qe.smp = "1"
      qe.advanced_network = true
      qe.net_mode = :vmnet_bridged
      qe.vmnet_interface = VMNET_INTERFACE
    end

    node.vm.synced_folder "fetcher-service", "/app", type: "rsync", rsync__exclude: RSYNC_EXCLUDES
    node.vm.provision "shell", path: "vagrant/fetcher/provision.sh"
  end

  config.vm.define "ui" do |node|
    node.vm.box = BOX
    node.vm.hostname = "skyivano-ui"
    node.vm.network "private_network", ip: NETWORK_IPS[:ui]

    node.vm.provider "qemu" do |qe|
      qe.ssh_port = 50113
      qe.memory = "1G"
      qe.smp = "2"
      qe.advanced_network = true
      qe.net_mode = :vmnet_bridged
      qe.vmnet_interface = VMNET_INTERFACE
    end

    node.vm.synced_folder "ui-service", "/app", type: "rsync", rsync__exclude: RSYNC_EXCLUDES
    node.vm.provision "shell", path: "vagrant/ui/provision.sh"
  end
end
