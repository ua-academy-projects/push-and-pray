# -*- mode: ruby -*-
# vi: set ft=ruby :

if File.exist?('.env')
  File.readlines('.env').each do |line|
    line.strip!
    next if line.empty? || line.start_with?('#')
    key, value = line.split('=', 2)
    ENV[key] = value.sub(/\A"(.*)"\Z/, '\1').sub(/\A'(.*)'\Z/, '\1')
  end
end

DB_NAME       = ENV['DB_NAME'] || "taska-db"
DB_USER       = ENV['DB_USER'] || "admin"
DB_PASSWORD   = ENV['DB_PASSWORD'] || "admin"

BRIDGE_DEVICE = ENV['BRIDGE_DEVICE'] || "enp2s0"
NETMASK       = ENV['NETMASK'] || "255.255.255.0"

IPS = {
  "db"                => ENV['DB_IP'] || "192.168.1.15",
  "backend"           => ENV['BACKEND_IP'] || "192.168.1.16",
  "proxy"             => ENV['PROXY_IP'] || "192.168.1.17",
  "poller"            => ENV['POLLER_IP'] || "192.168.1.18",
  "ui"                => ENV['UI_IP'] || "192.168.1.19",
}

VMS = {

  "db" => {
    hostname:      "db",
    synced_folder: "infrastructure",
    provision:     "./provision/db.sh",
    env: {
      "DB_NAME"     => DB_NAME,
      "DB_USER"     => DB_USER,
      "DB_PASSWORD" => DB_PASSWORD,
    },
  },

  "backend" => {
    hostname:      "backend-service",
    synced_folder: "backend",
    provision:     "./provision/backend.sh",
    env: {
      "DB_HOST"     => IPS["db"],
      "DB_NAME"     => DB_NAME,
      "DB_USER"     => DB_USER,
      "DB_PASSWORD" => DB_PASSWORD,
      "RABBITMQ_URL" => "amqp://admin:admin@#{IPS['db']}:5672/",
    },
  },

  "proxy" => {
    hostname:      "proxy-service",
    synced_folder: "proxy",
    provision:     "./provision/proxy.sh",
    env: {
      "RABBITMQ_URL" => "amqp://admin:admin@#{IPS['db']}:5672/",
    },
  },

  "poller" => {
    hostname:      "poller",
    synced_folder: "poller-service",
    provision:     "./provision/poller.sh",
    env: {
      "PROXY_SERVICE_URL" => "http://#{IPS['proxy']}:5001",
    },
  },

  "ui" => {
    hostname:      "ui",
    synced_folder: "ui-service",
    provision:     "./provision/ui.sh",
    forwarded_ports: [
      { guest: 5000, host: 5000, host_ip: "0.0.0.0" }
    ],
    env: {
      "BACKEND_SERVICE_URL" => "http://#{IPS['backend']}:5002",
      "REDIS_HOST"        => IPS["db"],
    },
  },

}

Vagrant.configure("2") do |config|

  config.vm.box = "generic/ubuntu2204"

  VMS.each do |name, opts|

    config.vm.define name do |node|

      node.vm.hostname = opts[:hostname]
      node.vm.provider "libvirt"

      node.vm.network "public_network",
        dev: BRIDGE_DEVICE,
        mode: "bridge",
        ip: IPS[name],
        netmask: NETMASK

      Array(opts[:forwarded_ports]).each do |fp|
        node.vm.network "forwarded_port", **fp
      end

      if opts[:synced_folder]
        node.vm.synced_folder opts[:synced_folder], "/vagrant/app"
      end

      node.vm.provision "shell",
        path: opts[:provision],
        env: opts[:env]

    end
  end
end
