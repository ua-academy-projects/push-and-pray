# -*- mode: ruby -*-
# vi: set ft=ruby :
if File.exist?('.env')
  File.readlines('.env').each do |line|
    line.strip!
    # Пропускаємо порожні рядки та коментарі
    next if line.empty? || line.start_with?('#')
    
    key, value = line.split('=', 2)
    # Зберігаємо в оточення Ruby, прибираючи можливі лапки
    ENV[key] = value.sub(/\A"(.*)"\Z/, '\1').sub(/\A'(.*)'\Z/, '\1')
  end
end
# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2204"

  IPS = {
    "db"      => "192.168.56.10",
    "backend" => "192.168.56.11",
    "proxy"   => "192.168.56.12",
    "poller"  => "192.168.56.13",
    "ui"      => "192.168.56.14",
  }
  DB_NAME     = ENV['DB_NAME'] || "taska-db"
  DB_USER     = ENV['DB_USER'] || "admin"
  DB_PASSWORD = ENV['DB_PASSWORD'] || "admin"
  BRIDGE_DEVICE = ENV['BRIDGE_DEVICE'] || "enp2s0"

  config.vm.define "db" do |db|
    db.vm.hostname = "db"
    db.vm.network "private_network", ip: IPS["db"]
    db.vm.provider "libvirt"
    db.vm.provision "shell", path: "./provision/db.sh", env: {
      "DB_NAME"     => DB_NAME,
      "DB_USER"     => DB_USER,
      "DB_PASSWORD" => DB_PASSWORD,
    }
  end

  # Backend — єдиний сервіс, що працює з PostgreSQL.
  config.vm.define "backend" do |backend|
    backend.vm.hostname = "backend-service"
    backend.vm.network "private_network", ip: IPS["backend"]
    backend.vm.synced_folder "backend", "/vagrant/app"
    backend.vm.provider "libvirt"
    backend.vm.provision "shell", path: "./provision/backend.sh", env: {
      "DB_HOST"     => IPS["db"],
      "DB_NAME"     => DB_NAME,
      "DB_USER"     => DB_USER,
      "DB_PASSWORD" => DB_PASSWORD,
    }
  end

  # Proxy викликає зовнішнє API та передає дані в Backend.
  config.vm.define "proxy" do |proxy|
    proxy.vm.hostname = "proxy-service"
    proxy.vm.network "private_network", ip: IPS["proxy"]
    proxy.vm.synced_folder "proxy", "/vagrant/app"
    proxy.vm.provider "libvirt"
    proxy.vm.provision "shell", path: "./provision/proxy.sh", env: {
      "BACKEND_IP" => IPS["backend"],
    }
  end

  config.vm.define "poller" do |poller|
    poller.vm.hostname = "poller"
    poller.vm.network "private_network", ip: IPS["poller"]
    poller.vm.synced_folder "poller-service", "/vagrant/app"
    poller.vm.provider "libvirt"
    poller.vm.provision "shell", path: "./provision/poller.sh", env: {
      "PROXY_IP" => IPS["proxy"],
    }
  end

  config.vm.define "ui" do |ui|
    ui.vm.hostname = "ui"
    # UI отримує адресу з DHCP локальної мережі та доступний з інших пристроїв.
    ui.vm.network "public_network", dev: BRIDGE_DEVICE
    ui.vm.network "private_network", ip: IPS["ui"]
    ui.vm.synced_folder "ui-service", "/vagrant/app"
    ui.vm.provider "libvirt"
    ui.vm.provision "shell", path: "./provision/ui.sh", env: {
      "PROXY_IP" => IPS["proxy"],
    }
  end
# Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine. In the example below,
  # accessing "localhost:8080" will access port 80 on the guest machine.
  # NOTE: This will enable public access to the opened port
  # config.vm.network "forwarded_port", guest: 80, host: 8080

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine and only allow access
  # via 127.0.0.1 to disable public access
  # config.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "127.0.0.1"

  # Create a private network, which allows host-only access to the machine
  # using a specific IP.
  # config.vm.network "private_network", ip: "192.168.33.10"

  # Create a public network, which generally matched to bridged network.
  # Bridged networks make the machine appear as another physical device on
  # your network.
  # config.vm.network "public_network"

  # Share an additional folder to the guest VM. The first argument is
  # the path on the host to the actual folder. The second argument is
  # the path on the guest to mount the folder. And the optional third
  # argument is a set of non-required options.
  # config.vm.synced_folder "../data", "/vagrant_data"

  # Disable the default share of the current code directory. Doing this
  # provides improved isolation between the vagrant box and your host
  # by making sure your Vagrantfile isn't accessible to the vagrant box.
  # If you use this you may want to enable additional shared subfolders as
  # shown above.
  # config.vm.synced_folder ".", "/vagrant", disabled: true

  # Provider-specific configuration so you can fine-tune various
  # backing providers for Vagrant. These expose provider-specific options.
  # Example for VirtualBox:
  #
  # config.vm.provider "virtualbox" do |vb|
  #   # Display the VirtualBox GUI when booting the machine
  #   vb.gui = true
  #
  #   # Customize the amount of memory on the VM:
  #   vb.memory = "1024"
  # end
  #
  # View the documentation for the provider you are using for more
  # information on available options.

  # Enable provisioning with a shell script. Additional provisioners such as
  # Ansible, Chef, Docker, Puppet and Salt are also available. Please see the
  # documentation for more information about their specific syntax and use.
  # config.vm.provision "shell", inline: <<-SHELL
  #   apt-get update
  #   apt-get install -y apache2
  # SHELL
end
