Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.box_architecture = "arm64"
  config.vm.box_check_update = false
  config.vm.boot_timeout = 600
  config.vm.synced_folder ".", "/vagrant"

  machines = [
    {
      name: "database",
      ip: "192.168.56.13",
      display_name: "weather-database",
      script: "providers/database.sh"
    },
    {
      name: "provider-service",
      ip: "192.168.56.12",
      display_name: "weather-provider-service",
      script: "providers/provider.sh"
    },
    {
      name: "backend-service",
      ip: "192.168.56.11",
      display_name: "weather-backend-service",
      script: "providers/backend.sh"
    },
    {
      name: "ui-service",
      ip: "192.168.56.10",
      display_name: "weather-ui-service",
      script: "providers/ui.sh"
    }
  ]

  machines.each do |machine|
    config.vm.define machine[:name] do |vm|
      vm.vm.hostname = machine[:name]

      vm.vm.network "private_network",
        ip: machine[:ip]

      if machine[:name] == "ui-service"
        vm.vm.network "forwarded_port",
          guest: 5000,
          host: 8080,
          host_ip: "0.0.0.0",
          protocol: "tcp",
          auto_correct: false
      end

      vm.vm.provider "vmware_desktop" do |vmware|
        vmware.vmx["displayName"] = machine[:display_name]
        vmware.vmx["memsize"] = "1024"
        vmware.vmx["numvcpus"] = "1"
        vmware.vmx["ethernet0.pcislotnumber"] = "160"
        vmware.vmx["ethernet1.pcislotnumber"] = "224"
      end

      vm.vm.provision "common",
        type: "shell",
        path: "providers/common.sh"

      vm.vm.provision machine[:name],
        type: "shell",
        path: machine[:script]
    end
  end
end
