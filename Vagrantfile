BOX = "perk/ubuntu-2204-arm64"
VMNET_INTERFACE = "en0"


# .env is excluded for the same reason .venv is: it's generated inside the guest by each
# service's provision.sh (cp .env.example .env, then a few sed rewrites for LAN IPs), never
# present in the host repo. Vagrant's rsync synced folder defaults to `--delete`, mirroring
# the guest directory to exactly match the host on every `vagrant up`/`reload` -- without this
# exclusion, that wipes .env on every restart that isn't a full `--provision` run, silently
# reverting every service back to its compiled-in config defaults (wrong RABBITMQ_URL host,
# etc.) until someone notices and manually re-provisions.
RSYNC_EXCLUDES = ["node_modules", ".venv", "__pycache__", ".pytest_cache", ".git", ".env"]

NODES = {
  postgres: {
    ip:        "192.168.0.220",
    ssh_port:  50110,
    memory:    "1G", # bumped from 512M -- this VM now also runs Redis (UI session storage) and RabbitMQ (Fetcher->Backend async queue)
    smp:       "1",
    provision: "vagrant/postgres/provision.sh",
  },
  backend: {
    ip:        "192.168.0.221",
    ssh_port:  50111,
    memory:    "1G", # bumped from 768M -- this VM now also runs a second Python process, the RabbitMQ consumer worker
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
