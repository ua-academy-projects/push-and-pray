
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-22.04"
  config.vm.boot_timeout = 1200
  config.ssh.keep_alive = true
  config.ssh.connect_timeout = 30

  bridge_adapter = ENV["VAGRANT_BRIDGE"]

  machines = {
    "db" => {
      memory: 3072,
      cpus: 2,
      provision: "provision/db.sh"
    },
    "backend" => {
      memory: 1536,
      cpus: 2,
      provision: "provision/backend.sh"
    },
    "fetcher" => {
      memory: 1024,
      cpus: 1,
      provision: "provision/fetcher.sh"
    },
    "ui" => {
      memory: 1024,
      cpus: 1,
      provision: "provision/ui.sh"
    }
  }

  machines.each do |name, settings|
    config.vm.define name do |vm|
      vm.vm.hostname = name

      if bridge_adapter && !bridge_adapter.empty?
        vm.vm.network "public_network",
          bridge: bridge_adapter,
          auto_config: true
      else
        vm.vm.network "public_network", auto_config: true
      end

    

      vm.vm.provider "virtualbox" do |vb|
        vb.name = "weather-#{name}"
        vb.gui = false
        vb.memory = settings[:memory]
        vb.cpus = settings[:cpus]
      end

      vm.vm.provision "shell",
        path: settings[:provision],
        privileged: true
    end
  end
end
