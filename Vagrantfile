# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'fileutils'

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

VM_SSH_USER = ENV['VM_SSH_USER'] || "user"
VM_SSH_PUBLIC_KEY_PATH = File.expand_path(
  ENV['VM_SSH_PUBLIC_KEY_PATH'] || "~/.ssh/vagrant-ssh.pub"
)

unless File.file?(VM_SSH_PUBLIC_KEY_PATH)
  raise "Public SSH key not found: #{VM_SSH_PUBLIC_KEY_PATH}"
end

VM_SSH_PUBLIC_KEY = File.read(VM_SSH_PUBLIC_KEY_PATH).strip
if VM_SSH_PUBLIC_KEY.empty?
  raise "Public SSH key is empty: #{VM_SSH_PUBLIC_KEY_PATH}"
end

BRIDGE_DEVICE = ENV['BRIDGE_DEVICE'] || "enp2s0"
NETMASK       = ENV['NETMASK'] || "255.255.255.224"

LAN_IPS = {
  "db"                => ENV['DB_IP'] || "192.168.1.15",
  "backend"           => ENV['BACKEND_IP'] || "192.168.1.16",
  "proxy"             => ENV['PROXY_IP'] || "192.168.1.17",
  "poller"            => ENV['POLLER_IP'] || "192.168.1.18",
  "ui"                => ENV['UI_IP'] || "192.168.1.19",
}

# This network is for host-to-VM administration.  It does not depend on the
# physical LAN bridge, so it keeps SSH working when libvirt uses macvtap for
# the public adapter.
SSH_IPS = {
  "db"                => ENV['SSH_DB_IP'] || "192.168.56.10",
  "backend"           => ENV['SSH_BACKEND_IP'] || "192.168.56.11",
  "proxy"             => ENV['SSH_PROXY_IP'] || "192.168.56.12",
  "poller"            => ENV['SSH_POLLER_IP'] || "192.168.56.13",
  "ui"                => ENV['SSH_UI_IP'] || "192.168.56.14",
  "logs"              => ENV['SSH_LOGS_IP'] || "192.168.56.15",
}

SSH_CONFIG_PATH = File.expand_path(ENV['SSH_CONFIG_PATH'] || "~/.ssh/config")
SSH_CONFIG_BEGIN = "# BEGIN academy-vagrant"
SSH_CONFIG_END = "# END academy-vagrant"

def write_ssh_config(path, aliases, ssh_user)
  FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
  existing = File.exist?(path) ? File.read(path) : ""
  managed_block = /^#{Regexp.escape(SSH_CONFIG_BEGIN)}\n.*?^#{Regexp.escape(SSH_CONFIG_END)}\n?/m
  retained = existing.gsub(managed_block, "").rstrip
  identity_file = File.expand_path("~/.ssh/vagrant-ssh")

  entries = aliases.map do |name, ip|
    <<~ENTRY
      Host #{name}
        HostName #{ip}
        User #{ssh_user}
        IdentityFile #{identity_file}
        IdentitiesOnly yes
    ENTRY
  end.join("\n")

  content = [retained, SSH_CONFIG_BEGIN, entries.rstrip, SSH_CONFIG_END].reject(&:empty?).join("\n\n") + "\n"
  File.write(path, content)
  File.chmod(0o600, path)
end

write_ssh_config(SSH_CONFIG_PATH, SSH_IPS, VM_SSH_USER)

VMS = {

  "logs" => {
    hostname:       "logs",
    provision:      "./provision/log-server.sh",
    public_network: false,
    docker:         false,
    env: {},
  },

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
      "DB_HOST"     => LAN_IPS["db"],
      "DB_NAME"     => DB_NAME,
      "DB_USER"     => DB_USER,
      "DB_PASSWORD" => DB_PASSWORD,
      "RABBITMQ_URL" => "amqp://admin:admin@#{LAN_IPS['db']}:5672/",
    },
  },

  "proxy" => {
    hostname:      "proxy-service",
    synced_folder: "proxy",
    provision:     "./provision/proxy.sh",
    env: {
      "RABBITMQ_URL" => "amqp://admin:admin@#{LAN_IPS['db']}:5672/",
    },
  },

  "poller" => {
    hostname:      "poller",
    synced_folder: "poller-service",
    provision:     "./provision/poller.sh",
    env: {
      "PROXY_SERVICE_URL" => "http://#{LAN_IPS['proxy']}:5001",
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
      "BACKEND_SERVICE_URL" => "http://#{LAN_IPS['backend']}:5002",
      "REDIS_HOST"        => LAN_IPS["db"],
    },
  },

}

Vagrant.configure("2") do |config|

  config.vm.box = "generic/ubuntu2204"

  VMS.each do |name, opts|

    config.vm.define name do |node|

      node.vm.hostname = opts[:hostname]
      node.vm.provider "libvirt"

      node.vm.network "private_network",
        ip: SSH_IPS[name],
        netmask: "255.255.255.0"

      unless opts[:public_network] == false
        node.vm.network "public_network",
          dev: BRIDGE_DEVICE,
          mode: "bridge",
          ip: LAN_IPS[name],
          netmask: NETMASK
      end

      Array(opts[:forwarded_ports]).each do |fp|
        node.vm.network "forwarded_port", **fp
      end

      if opts[:synced_folder]
        node.vm.synced_folder opts[:synced_folder], "/vagrant/app"
      end

      node.vm.provision "shell",
        path: "./provision/user.sh",
        env: {
          "VM_SSH_USER" => VM_SSH_USER,
          "VM_SSH_PUBLIC_KEY" => VM_SSH_PUBLIC_KEY,
        }

      node.vm.provision "shell",
        path: opts[:provision],
        env: opts[:env]

      unless opts[:docker] == false
        node.vm.provision "shell",
          path: "./provision/docker-user.sh",
          env: { "VM_SSH_USER" => VM_SSH_USER }
      end

      unless name == "logs"
        node.vm.provision "shell",
          path: "./provision/log-client.sh",
          env: {
            "LOG_SERVER_URL" => "http://#{SSH_IPS['logs']}:19532",
          }
      end

    end
  end
end
