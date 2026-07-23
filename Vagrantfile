# frozen_string_literal: true

VAGRANT_API_VERSION = "2"
BOX_NAME = ENV.fetch("AIRAWARE_VAGRANT_BOX", "bento/ubuntu-24.04")

NETWORK = {
  prefix: ENV.fetch("AIRAWARE_NETWORK_PREFIX", "192.168.50"),
  netmask: ENV.fetch("AIRAWARE_NETMASK", "255.255.255.0"),
  bridge: ENV.fetch(
    "AIRAWARE_BRIDGE_ADAPTER",
    "Intel(R) Wi-Fi 6 AX200 160MHz"
  )
}.freeze

DATABASE = {
  name: ENV.fetch("AIRAWARE_DB_NAME", "airaware"),
  user: ENV.fetch("AIRAWARE_DB_USER", "airaware_user"),
  password: ENV.fetch(
    "AIRAWARE_DB_PASSWORD",
    "airaware_dev_password"
  )
}.freeze

# The order is intentional:
# database -> backend -> fetcher -> frontend
#
# This gives dependent services the best chance of finding their
# dependencies ready during the first complete `vagrant up`.
MACHINES = {
  "database" => {
    hostname: "airaware-database",
    ip_suffix: 213,
    memory: 1024,
    cpus: 1,
    type: :database
  },
  "backend" => {
    hostname: "airaware-backend",
    ip_suffix: 211,
    memory: 768,
    cpus: 1,
    type: :application
  },
  "fetcher" => {
    hostname: "airaware-fetcher",
    ip_suffix: 212,
    memory: 768,
    cpus: 1,
    type: :application
  },
  "frontend" => {
    hostname: "airaware-frontend",
    ip_suffix: 210,
    memory: 768,
    cpus: 1,
    type: :application,
    primary: true
  }
}.freeze


def machine_ip(settings)
  "#{NETWORK.fetch(:prefix)}.#{settings.fetch(:ip_suffix)}"
end


def validate_configuration!
  supported_types = %i[application database]

  ip_suffixes = MACHINES.values.map do |settings|
    settings.fetch(:ip_suffix)
  end

  unless ip_suffixes.uniq.length == ip_suffixes.length
    raise "Every virtual machine must have a unique IP suffix"
  end

  MACHINES.each do |name, settings|
    required_keys = %i[hostname ip_suffix memory cpus type]

    missing_keys = required_keys.reject do |key|
      settings.key?(key)
    end

    unless missing_keys.empty?
      raise(
        "Machine '#{name}' is missing settings: " \
        "#{missing_keys.join(', ')}"
      )
    end

    unless settings.fetch(:ip_suffix).between?(2, 254)
      raise(
        "Machine '#{name}' has an invalid IP suffix: " \
        "#{settings.fetch(:ip_suffix)}"
      )
    end

    unless supported_types.include?(settings.fetch(:type))
      raise(
        "Machine '#{name}' has unsupported type: " \
        "#{settings.fetch(:type)}"
      )
    end
  end

  required_files = [
    "provision/common.sh",
    "provision/application.sh",
    "provision/database.sh",
    "backend-service/database/init.sql"
  ]

  missing_files = required_files.reject do |path|
    File.file?(File.expand_path(path, __dir__))
  end

  return if missing_files.empty?

  raise(
    "Required project files are missing: " \
    "#{missing_files.join(', ')}"
  )
end


validate_configuration!

VM_IPS = MACHINES.transform_values do |settings|
  machine_ip(settings)
end.freeze

COMMON_ENV = {
  "AIRAWARE_FRONTEND_IP" => VM_IPS.fetch("frontend"),
  "AIRAWARE_BACKEND_IP" => VM_IPS.fetch("backend"),
  "AIRAWARE_FETCHER_IP" => VM_IPS.fetch("fetcher"),
  "AIRAWARE_DATABASE_IP" => VM_IPS.fetch("database"),
  "AIRAWARE_DB_NAME" => DATABASE.fetch(:name),
  "AIRAWARE_DB_USER" => DATABASE.fetch(:user),
  "AIRAWARE_DB_PASSWORD" => DATABASE.fetch(:password)
}.freeze


Vagrant.configure(VAGRANT_API_VERSION) do |config|
  config.vm.box = BOX_NAME
  config.vm.box_check_update = false
  config.vm.boot_timeout = 600

  MACHINES.each do |name, settings|
    config.vm.define(
      name,
      primary: settings.fetch(:primary, false)
    ) do |machine|
      ip_address = machine_ip(settings)

      machine.vm.hostname = settings.fetch(:hostname)

      # Adapter 1 remains Vagrant's NAT adapter.
      # This bridged adapter places the VM on the home LAN.
      machine.vm.network(
        "public_network",
        bridge: NETWORK.fetch(:bridge),
        ip: ip_address,
        netmask: NETWORK.fetch(:netmask)
      )

      machine.vm.provider "virtualbox" do |virtualbox|
        virtualbox.name = settings.fetch(:hostname)
        virtualbox.gui = false
        virtualbox.memory = settings.fetch(:memory)
        virtualbox.cpus = settings.fetch(:cpus)
      end

      provision_env = COMMON_ENV.merge(
        "AIRAWARE_ROLE" => name,
        "AIRAWARE_VM_IP" => ip_address,
        "AIRAWARE_HOSTNAME" => settings.fetch(:hostname)
      )

      machine.vm.provision(
        "common",
        type: "shell",
        path: "provision/common.sh",
        env: provision_env
      )

      case settings.fetch(:type)
      when :database
        machine.vm.provision(
          "database",
          type: "shell",
          path: "provision/database.sh",
          env: provision_env
        )

      when :application
        machine.vm.provision(
          name,
          type: "shell",
          path: "provision/application.sh",
          env: provision_env
        )

      else
        raise "No provisioner configured for #{name}"
      end
    end
  end
end