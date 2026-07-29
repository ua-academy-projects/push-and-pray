# frozen_string_literal: true

VAGRANTFILE_API_VERSION = "2"
UBUNTU_BOX = "bento/ubuntu-24.04"
PROVIDER_SECRET_FILE = File.expand_path(
  ENV.fetch("AEGIS_PROVIDER_SECRET_FILE", "~/.config/aegis/abuseipdb-api-key"),
)
DATABASE_SECRET_FILE = File.expand_path(
  ENV.fetch("AEGIS_DATABASE_SECRET_FILE", "~/.config/aegis/mariadb-password"),
)
DATABASE_ROOT_SECRET_FILE = File.expand_path(
  ENV.fetch(
    "AEGIS_DATABASE_ROOT_SECRET_FILE",
    "~/.config/aegis/mariadb-root-password",
  ),
)
REDIS_SECRET_FILE = File.expand_path(
  ENV.fetch("AEGIS_REDIS_SECRET_FILE", "~/.config/aegis/redis-ui-password"),
)
RABBITMQ_PROVIDER_SECRET_FILE = File.expand_path(
  ENV.fetch(
    "AEGIS_RABBITMQ_PROVIDER_SECRET_FILE",
    "~/.config/aegis/rabbitmq-provider-password",
  ),
)
RABBITMQ_HISTORY_SECRET_FILE = File.expand_path(
  ENV.fetch(
    "AEGIS_RABBITMQ_HISTORY_SECRET_FILE",
    "~/.config/aegis/rabbitmq-history-password",
  ),
)
RABBITMQ_ADMIN_SECRET_FILE = File.expand_path(
  ENV.fetch(
    "AEGIS_RABBITMQ_ADMIN_SECRET_FILE",
    "~/.config/aegis/rabbitmq-admin-password",
  ),
)

VMS = {
  "infra-vm" => {
    ip: "192.168.100.14",
    cpus: 2,
    memory: 2048,
    infrastructure: true,
    firewall_role: "infra",
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
  # VirtualBox shared folders work from native Windows paths and expose the
  # checkout at the same guest path used by every Compose build context.
  config.vm.synced_folder ".",
    "/vagrant",
    type: "virtualbox",
    mount_options: ["dmode=775", "fmode=664"]
  config.vm.post_up_message = <<~MESSAGE
    AEGIS is running on four VirtualBox VMs.
    UI: http://192.168.100.10:8000
    RabbitMQ management: http://192.168.100.14:15672
    Use 'vagrant status' and 'vagrant ssh <vm>' from PowerShell for diagnostics.
  MESSAGE

  VMS.each do |name, settings|
    config.vm.define name do |machine|
      machine.vm.hostname = name
      machine.vm.network "public_network", ip: settings.fetch(:ip)

      # VirtualBox-specific resource settings are intentionally kept together.
      machine.vm.provider "virtualbox" do |virtualbox|
        virtualbox.name = "aegis-#{name}"
        virtualbox.cpus = settings.fetch(:cpus)
        virtualbox.memory = settings.fetch(:memory)
        virtualbox.gui = false
        virtualbox.customize ["modifyvm", :id, "--graphicscontroller", "vboxsvga"]
        virtualbox.customize ["modifyvm", :id, "--accelerate3d", "off"]
        virtualbox.customize ["modifyvm", :id, "--vram", "32"]
        virtualbox.customize ["modifyvm", :id, "--paravirtprovider", "kvm"]
        virtualbox.customize ["modifyvm", :id, "--nested-hw-virt", "off"]
      end

      machine.vm.provision "shell", privileged: false, inline: <<~SHELL
        echo "Hostname: $(hostname)"
        echo "Assigned addresses: $(hostname -I)"
      SHELL

      # Common OS tooling and directories must exist before a service-specific
      # application image is built or any application container is started.
      machine.vm.provision "shell", path: "provision/base-vm.sh"

      if settings.key?(:service)
        machine.vm.provision "shell",
          path: "provision/app-vm.sh",
          args: [settings.fetch(:service), settings.fetch(:package)]
      end

      if settings[:deploy_provider]
        machine.vm.provision "file",
          source: PROVIDER_SECRET_FILE,
          destination: "/tmp/aegis-provider-api-key"
        machine.vm.provision "file",
          source: RABBITMQ_PROVIDER_SECRET_FILE,
          destination: "/tmp/aegis-rabbitmq-provider-password"
        machine.vm.provision "shell", path: "provision/provider-vm.sh"
      end

      if settings[:deploy_history]
        machine.vm.provision "file",
          source: DATABASE_SECRET_FILE,
          destination: "/tmp/aegis-mariadb-password"
        machine.vm.provision "file",
          source: RABBITMQ_HISTORY_SECRET_FILE,
          destination: "/tmp/aegis-rabbitmq-history-password"
        machine.vm.provision "shell", path: "provision/history-vm.sh"
      end

      if settings[:infrastructure]
        {
          DATABASE_SECRET_FILE => "/tmp/aegis-mariadb-password",
          DATABASE_ROOT_SECRET_FILE => "/tmp/aegis-mariadb-root-password",
          RABBITMQ_PROVIDER_SECRET_FILE => "/tmp/aegis-rabbitmq-provider-password",
          RABBITMQ_HISTORY_SECRET_FILE => "/tmp/aegis-rabbitmq-history-password",
          RABBITMQ_ADMIN_SECRET_FILE => "/tmp/aegis-rabbitmq-admin-password",
          REDIS_SECRET_FILE => "/tmp/aegis-redis-password",
        }.each do |source, destination|
          machine.vm.provision "file", source: source, destination: destination
        end
        machine.vm.provision "shell", path: "provision/infra-vm.sh"
      end

      if settings[:deploy_ui]
        machine.vm.provision "file",
          source: REDIS_SECRET_FILE,
          destination: "/tmp/aegis-redis-password"
        machine.vm.provision "shell", path: "provision/ui-vm.sh"
      end

      machine.vm.provision "shell",
        path: "provision/firewall.sh",
        args: [settings.fetch(:firewall_role)]
    end
  end
end
