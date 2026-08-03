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

REDIS = {
  password: ENV.fetch(
    "AIRAWARE_REDIS_PASSWORD",
    "airaware_redis_dev_password"
  )
}.freeze

RABBITMQ = {
  user: ENV.fetch("AIRAWARE_RABBITMQ_USER", "airaware"),
  password: ENV.fetch(
    "AIRAWARE_RABBITMQ_PASSWORD",
    "airaware_rabbitmq_dev_password"
  ),
  vhost: ENV.fetch("AIRAWARE_RABBITMQ_VHOST", "airaware")
}.freeze

FRONTEND = {
  secret_key: ENV.fetch(
    "AIRAWARE_FLASK_SECRET_KEY",
    "airaware_flask_development_secret"
  )
}.freeze

# Vagrant creates and networks the VMs. Provisioning installs Docker
# and launches one Docker Compose project on each VM.
MACHINES = {
  "database" => {
    hostname: "airaware-database",
    ip_suffix: 213,
    memory: 2048,
    cpus: 2,
    primary: false
  },
  "backend" => {
    hostname: "airaware-backend",
    ip_suffix: 211,
    memory: 1024,
    cpus: 1,
    primary: false
  },
  "fetcher" => {
    hostname: "airaware-fetcher",
    ip_suffix: 212,
    memory: 768,
    cpus: 1,
    primary: false
  },
  "frontend" => {
    hostname: "airaware-frontend",
    ip_suffix: 210,
    memory: 768,
    cpus: 1,
    primary: true
  }
}.freeze


def machine_ip(settings)
  "#{NETWORK.fetch(:prefix)}.#{settings.fetch(:ip_suffix)}"
end


def validate_configuration!
  suffixes = MACHINES.values.map { |settings| settings.fetch(:ip_suffix) }
  raise "Every VM must have a unique IP suffix" unless suffixes.uniq.length == suffixes.length

  required_files = [
    "provision/common.sh",
    "provision/docker.sh",
    "provision/deploy.sh",
    "deploy/frontend/compose.yml",
    "deploy/backend/compose.yml",
    "deploy/fetcher/compose.yml",
    "deploy/infrastructure/compose.yml",
    "frontend-service/Dockerfile",
    "backend-service/Dockerfile",
    "api-fetcher-service/Dockerfile",
    "backend-service/database/init.sql"
  ]

  missing_files = required_files.reject do |path|
    File.file?(File.expand_path(path, __dir__))
  end

  return if missing_files.empty?

  raise "Required project files are missing: #{missing_files.join(', ')}"
end


validate_configuration!

VM_IPS = MACHINES.transform_values { |settings| machine_ip(settings) }.freeze

COMMON_ENV = {
  "AIRAWARE_FRONTEND_IP" => VM_IPS.fetch("frontend"),
  "AIRAWARE_BACKEND_IP" => VM_IPS.fetch("backend"),
  "AIRAWARE_FETCHER_IP" => VM_IPS.fetch("fetcher"),
  "AIRAWARE_DATABASE_IP" => VM_IPS.fetch("database"),
  "AIRAWARE_DB_NAME" => DATABASE.fetch(:name),
  "AIRAWARE_DB_USER" => DATABASE.fetch(:user),
  "AIRAWARE_DB_PASSWORD" => DATABASE.fetch(:password),
  "AIRAWARE_REDIS_PASSWORD" => REDIS.fetch(:password),
  "AIRAWARE_FLASK_SECRET_KEY" => FRONTEND.fetch(:secret_key),
  "AIRAWARE_RABBITMQ_USER" => RABBITMQ.fetch(:user),
  "AIRAWARE_RABBITMQ_PASSWORD" => RABBITMQ.fetch(:password),
  "AIRAWARE_RABBITMQ_VHOST" => RABBITMQ.fetch(:vhost)
}.freeze

Vagrant.configure(VAGRANT_API_VERSION) do |config|
  config.vm.box = BOX_NAME
  config.vm.box_check_update = false
  config.vm.boot_timeout = 600

  MACHINES.each do |name, settings|
    config.vm.define(name, primary: settings.fetch(:primary)) do |machine|
      ip_address = machine_ip(settings)
      machine.vm.hostname = settings.fetch(:hostname)

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

      machine.vm.provision(
        "docker",
        type: "shell",
        path: "provision/docker.sh",
        env: provision_env
      )

      machine.vm.provision(
        "compose",
        type: "shell",
        path: "provision/deploy.sh",
        env: provision_env
      )
    end
  end
end
