# frozen_string_literal: true

VAGRANTFILE_API_VERSION = "2"
UBUNTU_BOX = "bento/ubuntu-24.04"
PROVIDER_SECRET_FILE = File.expand_path(
  ENV.fetch("AEGIS_PROVIDER_SECRET_FILE", "~/.config/aegis/abuseipdb-api-key"),
)
DATABASE_SECRET_FILE = File.expand_path(
  ENV.fetch("AEGIS_DATABASE_SECRET_FILE", "~/.config/aegis/mariadb-password"),
)

VMS = {
  "db-vm" => {
    ip: "192.168.100.13",
    cpus: 1,
    memory: 1024,
    database: true,
    firewall_role: "db",
  },
  "provider-vm" => {
    ip: "192.168.100.12",
    cpus: 1,
    memory: 1024,
    service: "provider-service",
    package: "provider_service",
    deploy_provider: true,
    firewall_role: "provider",
  },
  "history-vm" => {
    ip: "192.168.100.11",
    cpus: 1,
    memory: 1024,
    service: "history-service",
    package: "history_service",
    deploy_history: true,
    firewall_role: "history",
  },
  "ui-vm" => {
    ip: "192.168.100.10",
    cpus: 1,
    memory: 1024,
    service: "ui-service",
    package: "ui_service",
    deploy_ui: true,
    firewall_role: "ui",
  },
}.freeze

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = UBUNTU_BOX

  VMS.each do |name, settings|
    config.vm.define name do |machine|
      machine.vm.hostname = name
      machine.vm.network "public_network", ip: settings.fetch(:ip), bridge: "Ethernet 4"

      # VirtualBox-specific resource settings are intentionally kept together.
      machine.vm.provider "virtualbox" do |virtualbox|
        virtualbox.name = "aegis-#{name}"
        virtualbox.cpus = settings.fetch(:cpus)
        virtualbox.memory = settings.fetch(:memory)
      end

      machine.vm.provision "shell", privileged: false, inline: <<~SHELL
        echo "Hostname: $(hostname)"
        echo "Assigned addresses: $(hostname -I)"
      SHELL

      if settings.key?(:service)
        machine.vm.provision "shell",
          path: "provision/app-vm.sh",
          args: [settings.fetch(:service), settings.fetch(:package)]
      end

      if settings[:deploy_provider]
        machine.vm.provision "file",
          source: PROVIDER_SECRET_FILE,
          destination: "/tmp/aegis-provider-api-key"
        machine.vm.provision "shell", path: "provision/provider-vm.sh"
      end

      if settings[:deploy_history]
        machine.vm.provision "file",
          source: DATABASE_SECRET_FILE,
          destination: "/tmp/aegis-mariadb-password"
        machine.vm.provision "shell", path: "provision/history-vm.sh"
      end

      if settings[:deploy_ui]
        machine.vm.provision "shell", path: "provision/ui-vm.sh"
        machine.trigger.after [:up, :provision] do |trigger|
          trigger.name = "Verify Aegis UI from the host"
          trigger.run = { inline: "bash provision/verify-ui-host.sh" }
        end
      end

      if settings[:database]
        machine.vm.provision "file",
          source: DATABASE_SECRET_FILE,
          destination: "/tmp/aegis-mariadb-password"
        machine.vm.provision "shell", path: "provision/db-vm.sh"
      end

      machine.vm.provision "shell",
        path: "provision/firewall.sh",
        args: [settings.fetch(:firewall_role)]
    end
  end
end
