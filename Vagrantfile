BOX = "perk/ubuntu-2204-arm64"
VMNET_INTERFACE = "en0"


RSYNC_EXCLUDES = ["node_modules", ".venv", "__pycache__", ".pytest_cache", ".git"]

NODES = {
  postgres: {
    ip:        "192.168.0.220",
    ssh_port:  50110,
    memory:    "512M",
    smp:       "1",
    provision: "vagrant/postgres/provision.sh",
  },
  backend: {
    ip:        "192.168.0.221",
    ssh_port:  50111,
    memory:    "768M",
    smp:       "1",
    sync:      "backend-service",
    provision: "vagrant/backend/provision.sh",
  },
  fetcher: {
    ip:        "192.168.0.222",
    ssh_port:  50112,
    memory:    "768M",
    smp:       "1",
    sync:      "fetcher-service",
    provision: "vagrant/fetcher/provision.sh",
  },
  ui: {
    ip:        "192.168.0.223",
    ssh_port:  50113,
    memory:    "1G",
    smp:       "2",
    sync:      "ui-service",
    provision: "vagrant/ui/provision.sh",
  },
}

Vagrant.configure("2") do |config|
  NODES.each do |name, opts|
    config.vm.define name.to_s do |node|
      node.vm.box = BOX
      node.vm.hostname = "skyivano-#{name}"
      node.vm.network "private_network", ip: opts[:ip]

      node.vm.provider "qemu" do |qe|
        qe.ssh_port = opts[:ssh_port]
        qe.memory = opts[:memory]
        qe.smp = opts[:smp]
        qe.advanced_network = true
        qe.net_mode = :vmnet_bridged
        qe.vmnet_interface = VMNET_INTERFACE
      end

      if opts[:sync]
        node.vm.synced_folder opts[:sync], "/app", type: "rsync", rsync__exclude: RSYNC_EXCLUDES
      end

      node.vm.provision "shell", path: opts[:provision]
    end
  end
end
