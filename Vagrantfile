Vagrant.configure("2") do |config|
  config.vm.box = "debian/bookworm64"
  ssh_pub_key = File.readlines("#{Dir.home}/.ssh/id_ed25519.pub").first.strip

  machines = [
    {
      name: "proxy", ip: "192.168.0.50", memory: "1024", cpus: 1,
      app_dir: "proxy", synced: "./proxy-service",
      forwarded: [{ guest: 8082, host: 8082 }],
      user: "proxyssh"
    },
    {
      name: "history", ip: "192.168.0.51", memory: "1024", cpus: 1,
      app_dir: "history", synced: "./history-service",
      forwarded: [{ guest: 8081, host: 8081 }],
      user: "historyssh"
    },
    {
      name: "ui", ip: "192.168.0.52", memory: "512", cpus: 1,
      app_dir: "ui", synced: "./ui-service",
      forwarded: [{ guest: 80, host: 8080 }],
      user: "uissh"
    },
    {
      name: "redis", ip: "192.168.0.53", memory: "2048", cpus: 1,
      app_dir: "redis", synced: "./redis",
      forwarded: [{ guest: 8083, host: 8083 }],
      user: "redissh"
    },
    {
      name: "rabbitmq", ip: "192.168.0.54", memory: "512", cpus: 1,
      app_dir: "rabbitmq", synced: "./rabbitmq-service",
      forwarded: [{ guest: 5672, host: 5672 }, { guest: 15672, host: 15672 }],
      user: "rabbitmqssh"
    },
    {
      name: "logserver", ip: "192.168.0.55", memory: "512", cpus: 1,
      user: "logserverssh", forwarded: [{guest:514, host: 514}]
    }
  ]

  machines.each do |m|
    config.vm.define m[:name] do |node|
      node.vm.hostname = m[:name]
      node.vm.network "public_network",
        bridge: "wlp3s0",
        ip: m[:ip]
      (m[:forwarded] || []).each do |p|
        node.vm.network "forwarded_port", guest: p[:guest], host: p[:host]
      end

      node.vm.synced_folder m[:synced], "/home/vagrant/#{m[:app_dir]}" if m[:synced]

      node.vm.provider "virtualbox" do |vb|
        vb.name = m[:name]
        vb.memory = m[:memory]
        vb.cpus = m[:cpus]
      end

      if m[:app_dir]
        node.vm.provision "shell", path: "provision/setup-docker.sh", args: [m[:app_dir]]
      end

      node.vm.provision "shell", path: "provision/setup-ssh.sh", args: [m[:user], ssh_pub_key]
      role = (m[:name] == "logserver") ? "server" : "client"

      node.vm.provision "file", source: "provision/certs/CA.pem",              destination: "/tmp/CA.pem"
      node.vm.provision "file", source: "provision/certs/#{role}-key.pem",     destination: "/tmp/#{role}-key.pem"
      node.vm.provision "file", source: "provision/certs/#{role}-cert.pem",    destination: "/tmp/#{role}-cert.pem"
      node.vm.provision "file", source: "provision/01-#{role}.conf",           destination: "/tmp/01-#{role}.conf"
      node.vm.provision "shell", path: "provision/setup-tls.sh", args: [role]
    end
  end
end