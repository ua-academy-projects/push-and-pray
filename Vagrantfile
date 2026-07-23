# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Four-VM dev environment for SkyIvano: one VM per component (postgres,
# history-service, backend-service, ui-service), run under the QEMU provider
# (vagrant-qemu plugin) since this host is Apple Silicon and VirtualBox's
# arm64 support is not reliable enough to import boxes on it.
#
# Networking: each VM only gets QEMU's default usermode ("slirp") NIC - no
# private_network/vmnet is configured, since that needs either sudo (vmnet)
# or an extra background daemon (socket_vmnet) on macOS. Instead, cross-VM
# calls go: guest -> its own slirp gateway alias 10.0.2.2 -> the real host ->
# the target VM's forwarded port. This needs no extra setup at all:
#
#   postgres  forwards 5432  (history connects to 10.0.2.2:5432)
#   history   forwards 8001  (backend connects to 10.0.2.2:8001)
#   backend   forwards 8000  (browser on the host uses http://localhost:8000)
#   ui        forwards 5173  (browser on the host uses http://localhost:5173)
#
# `vagrant up` brings machines up in the order defined below, matching this
# dependency chain (postgres -> history -> backend -> ui).
#
# Synced folders use rsync (one-directional, host -> guest) rather than SMB:
# SMB synced folders need a manual "File Sharing" toggle in macOS System
# Settings plus a password prompt, which isn't worth the friction here. rsync
# pushes on `vagrant up`/`vagrant reload`/`vagrant provision`; for live sync
# while editing, run `vagrant rsync-auto` in another terminal.

BOX = "perk/ubuntu-2204-arm64"

# node_modules/.venv are guest-built (Linux/arm64) - never rsync them from
# the host (macOS/arm64 has OS-specific native bindings that won't run in
# the guest), so the guest's own npm install / venv survives every re-sync.
RSYNC_EXCLUDES = ["node_modules", ".venv", "__pycache__", ".pytest_cache", ".git"]

Vagrant.configure("2") do |config|
  config.vm.define "postgres" do |node|
    node.vm.box = BOX
    node.vm.hostname = "skyivano-postgres"
    node.vm.network "forwarded_port", guest: 5432, host: 5432, auto_correct: true

    node.vm.provider "qemu" do |qe|
      qe.ssh_port = 50110
      qe.memory = "512M"
      qe.smp = "1"
    end

    node.vm.provision "shell", path: "vagrant/postgres/provision.sh"
  end

  config.vm.define "history" do |node|
    node.vm.box = BOX
    node.vm.hostname = "skyivano-history"
    node.vm.network "forwarded_port", guest: 8001, host: 8001

    node.vm.provider "qemu" do |qe|
      qe.ssh_port = 50111
      qe.memory = "768M"
      qe.smp = "1"
    end

    node.vm.synced_folder "history-service", "/app", type: "rsync", rsync__exclude: RSYNC_EXCLUDES
    node.vm.provision "shell", path: "vagrant/history/provision.sh"
  end

  config.vm.define "backend" do |node|
    node.vm.box = BOX
    node.vm.hostname = "skyivano-backend"
    node.vm.network "forwarded_port", guest: 8000, host: 8000

    node.vm.provider "qemu" do |qe|
      qe.ssh_port = 50112
      qe.memory = "768M"
      qe.smp = "1"
    end

    node.vm.synced_folder "backend-service", "/app", type: "rsync", rsync__exclude: RSYNC_EXCLUDES
    node.vm.provision "shell", path: "vagrant/backend/provision.sh"
  end

  config.vm.define "ui" do |node|
    node.vm.box = BOX
    node.vm.hostname = "skyivano-ui"
    node.vm.network "forwarded_port", guest: 5173, host: 5173

    node.vm.provider "qemu" do |qe|
      qe.ssh_port = 50113
      qe.memory = "1G"
      qe.smp = "2"
    end

    node.vm.synced_folder "ui-service", "/app", type: "rsync", rsync__exclude: RSYNC_EXCLUDES
    node.vm.provision "shell", path: "vagrant/ui/provision.sh"
  end
end
