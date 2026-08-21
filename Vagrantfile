# frozen_string_literal: true

require "ipaddr"

def load_project_settings(path)
  return {} unless File.file?(path)

  File.readlines(path).each_with_object({}) do |line, values|
    stripped = line.strip
    next if stripped.empty? || stripped.start_with?("#") || !stripped.include?("=")

    key, value = stripped.split("=", 2)
    values[key.strip] = value.strip.gsub(/\A["']|["']\z/, "")
  end
end

settings = load_project_settings(File.join(__dir__, "infrastructure/vagrant/config/vagrant.env"))
box_name = ENV.fetch("VAGRANT_BOX", settings.fetch("VAGRANT_BOX", "cloud-image/ubuntu-24.04"))
box_version = ENV.fetch("VAGRANT_BOX_VERSION", settings.fetch("VAGRANT_BOX_VERSION", ""))
box_architecture = ENV.fetch(
  "VAGRANT_BOX_ARCHITECTURE",
  settings.fetch("VAGRANT_BOX_ARCHITECTURE", "arm64")
)
qemu_interface = ENV.fetch(
  "QEMU_VMNET_INTERFACE",
  settings.fetch("QEMU_VMNET_INTERFACE", "en0")
)
ssh_admin_user = ENV.fetch(
  "SSH_ADMIN_USER",
  settings.fetch("SSH_ADMIN_USER", "oiladmin")
)
ssh_private_key_path = File.expand_path(
  ENV.fetch(
    "SSH_PRIVATE_KEY_PATH",
    settings.fetch("SSH_PRIVATE_KEY_PATH", "~/.ssh/oil_tracker_ed25519")
  )
)
ssh_public_key_path = "#{ssh_private_key_path}.pub"
lan_cidr = ENV.fetch("LAN_CIDR", settings.fetch("LAN_CIDR", "192.168.88.0/24"))
lan_netmask = ENV.fetch("LAN_NETMASK", settings.fetch("LAN_NETMASK", "255.255.255.0"))

machines = {
  "database" => {
    hostname: "oil-db",
    lan_ip: settings.fetch("DB_LAN_IP", ""),
    memory: 1024,
    cpus: 1,
    ssh_port: 50022,
    provisioner: "infrastructure/vagrant/provisioning/database.sh"
  },
  "history" => {
    hostname: "oil-history",
    lan_ip: settings.fetch("HISTORY_LAN_IP", ""),
    memory: 2048,
    cpus: 1,
    ssh_port: 50023,
    provisioner: "infrastructure/vagrant/provisioning/history.sh"
  },
  "fetcher" => {
    hostname: "oil-fetcher",
    lan_ip: settings.fetch("FETCHER_LAN_IP", ""),
    memory: 1024,
    cpus: 1,
    ssh_port: 50024,
    provisioner: "infrastructure/vagrant/provisioning/fetcher.sh"
  },
  "ui" => {
    hostname: "oil-ui",
    lan_ip: settings.fetch("UI_LAN_IP", ""),
    memory: 2048,
    cpus: 1,
    ssh_port: 50025,
    provisioner: "infrastructure/vagrant/provisioning/ui.sh"
  }
}.freeze

missing_lan_ips = machines.filter_map { |name, machine| name if machine[:lan_ip].empty? }
unless missing_lan_ips.empty?
  raise <<~MESSAGE
    Missing static LAN IPs for: #{missing_lan_ips.join(", ")}.
    Set DB_LAN_IP, HISTORY_LAN_IP, FETCHER_LAN_IP and UI_LAN_IP in
    infrastructure/vagrant/config/vagrant.env. Every VM must have a reserved address in #{lan_cidr}.
  MESSAGE
end

lan_network = IPAddr.new(lan_cidr)
lan_ips = machines.values.map { |machine| machine[:lan_ip] }
raise "Every *_LAN_IP must be unique." unless lan_ips.uniq.length == lan_ips.length
unless ssh_admin_user.match?(/\A[a-z_][a-z0-9_-]{0,31}\z/)
  raise "SSH_ADMIN_USER must be a valid Linux username."
end
unless File.file?(ssh_public_key_path)
  raise <<~MESSAGE
    Missing SSH public key: #{ssh_public_key_path}
    Run ./infrastructure/vagrant/commands/ssh-setup.sh before provisioning.
  MESSAGE
end

machines.each do |name, machine|
  ip = IPAddr.new(machine[:lan_ip])
  raise "#{name} IP #{ip} is outside LAN_CIDR #{lan_cidr}." unless lan_network.include?(ip)
  raise "#{name} IP #{ip} cannot be a network or broadcast address." if ip == lan_network.to_range.first || ip == lan_network.to_range.last
end

Vagrant.configure("2") do |config|
  config.vm.box = box_name
  config.vm.box_version = box_version unless box_version.empty?
  config.vm.box_architecture = box_architecture unless box_architecture.empty?
  config.vm.boot_timeout = 900
  config.ssh.insert_key = true
  config.vm.synced_folder ".", "/vagrant",
    type: "rsync",
    rsync__exclude: [
      ".env",
      ".git/",
      ".venv/",
      ".vagrant/",
      ".pytest_cache/",
      ".ruff_cache/",
      "**/__pycache__/",
      "**/node_modules/"
    ]

  machines.each do |name, machine|
    config.vm.define name, primary: name == "ui" do |node|
      node.vm.hostname = machine[:hostname]

      # vagrant-qemu 0.6.x maps this high-level private_network declaration
      # to its second, vmnet-bridged NIC. The address is a real LAN address.
      node.vm.network "private_network",
        ip: machine[:lan_ip],
        netmask: lan_netmask

      node.vm.provider "qemu" do |provider|
        provider.memory = "#{machine[:memory]}M"
        provider.smp = machine[:cpus].to_s
        provider.ssh_port = machine[:ssh_port].to_s
        provider.ssh_auto_correct = true
        provider.advanced_network = true
        provider.net_mode = :vmnet_bridged
        provider.vmnet_interface = qemu_interface
        # QEMU's -daemonize forks after macOS frameworks have initialized,
        # which can trigger Objective-C fork-safety crashes on Apple Silicon.
        # Let Vagrant detach the process instead of making QEMU fork itself.
        provider.no_daemonize = true if RUBY_PLATFORM.include?("darwin")
      end

      node.vm.provision "shell", name: "common", path: "infrastructure/vagrant/provisioning/common.sh"
      # Docker is intentionally installed by our shell script. The native
      # Vagrant Docker and Docker Compose provisioners are not used.
      node.vm.provision "shell",
        name: "docker-install",
        path: "infrastructure/vagrant/provisioning/docker-install.sh"
      node.vm.provision "file",
        source: ssh_public_key_path,
        destination: "/tmp/oil-tracker-admin.pub"
      node.vm.provision "shell",
        name: "ssh-access",
        path: "infrastructure/vagrant/provisioning/ssh-access.sh"
      node.vm.provision "shell",
        name: "logging",
        path: "infrastructure/vagrant/provisioning/logging.sh"
      role = File.basename(machine[:provisioner], ".sh")
      node.vm.provision "shell",
        name: role,
        path: machine[:provisioner],
        env: {
          "DB_PASSWORD" => ENV.fetch("DB_PASSWORD", ""),
          "OILPRICEAPI_KEY" => ENV.fetch("OILPRICEAPI_KEY", ""),
          "RABBITMQ_USER" => ENV.fetch("RABBITMQ_USER", ""),
          "RABBITMQ_PASSWORD" => ENV.fetch("RABBITMQ_PASSWORD", "")
        }
    end
  end
end
