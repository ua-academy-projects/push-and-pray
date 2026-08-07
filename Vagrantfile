def read_deploy_settings
  settings = {}
  path = File.join(__dir__, "deploy.env")
  return settings unless File.exist?(path)

  File.foreach(path) do |line|
    stripped = line.strip
    next if stripped.empty? || stripped.start_with?("#")

    key, value = stripped.split("=", 2)
    settings[key] = value.to_s.gsub(/\A['"]|['"]\z/, "")
  end
  settings
end

settings = read_deploy_settings
value = lambda do |name, default|
  ENV.fetch(name, settings.fetch(name, default))
end

lan_netmask = value.call("LAN_NETMASK", "255.255.255.0")
bridge_name = value.call("WILDLIFE_BRIDGE", "")

machines = {
  "database" => {
    ip: value.call("DB_HOST", "192.168.10.210"),
    memory: 1024
  },
  "redis" => {
    ip: value.call("REDIS_HOST", "192.168.10.214"),
    memory: 768
  },
  "fetcher" => {
    ip: value.call("FETCHER_HOST", "192.168.10.212"),
    memory: 768
  },
  "backend" => {
    ip: value.call("BACKEND_HOST", "192.168.10.211"),
    memory: 1536
  },
  "ui" => {
    ip: value.call("UI_HOST", "192.168.10.213"),
    memory: 768
  },
  "logging" => {
    ip: value.call("LOGGING_HOST", "192.168.10.215"),
    memory: 512
  }
}

provision_environment = {
  "PROJECT_ROOT" => "/vagrant",
  "VM_ADMIN_USER" => value.call("VM_ADMIN_USER", "wildlife"),
  "LAN_CIDR" => value.call("LAN_CIDR", "192.168.10.0/24"),
  "DB_HOST" => machines["database"][:ip],
  "BACKEND_HOST" => machines["backend"][:ip],
  "FETCHER_HOST" => machines["fetcher"][:ip],
  "UI_HOST" => machines["ui"][:ip],
  "REDIS_HOST" => machines["redis"][:ip],
  "LOGGING_HOST" => machines["logging"][:ip],
  "DB_NAME" => value.call("DB_NAME", "wildlife"),
  "DB_USER" => value.call("DB_USER", "wildlife_user"),
  "DB_PASSWORD" => value.call("DB_PASSWORD", "wildlife_password"),
  "REDIS_PASSWORD" => value.call(
    "REDIS_PASSWORD",
    "wildlife_redis_password"
  ),
  "RABBITMQ_USER" => value.call("RABBITMQ_USER", "wildlife_queue"),
  "RABBITMQ_PASSWORD" => value.call(
    "RABBITMQ_PASSWORD",
    "wildlife_queue_password"
  ),
  "RABBITMQ_QUEUE" => value.call(
    "RABBITMQ_QUEUE",
    "wildlife.refresh"
  ),
  "INTERNAL_SERVICE_TOKEN" => value.call(
    "INTERNAL_SERVICE_TOKEN",
    "change-this-internal-service-token"
  ),
  "FETCHER_PUBLISH_ATTEMPTS" => value.call(
    "FETCHER_PUBLISH_ATTEMPTS",
    "5"
  ),
  "FETCHER_RETRY_DELAY_SECONDS" => value.call(
    "FETCHER_RETRY_DELAY_SECONDS",
    "10"
  ),
  "BACKEND_PROCESS_ATTEMPTS" => value.call(
    "BACKEND_PROCESS_ATTEMPTS",
    "3"
  ),
  "BACKEND_RETRY_DELAY_SECONDS" => value.call(
    "BACKEND_RETRY_DELAY_SECONDS",
    "30"
  ),
  "SESSION_LIFETIME_DAYS" => value.call(
    "SESSION_LIFETIME_DAYS",
    "30"
  ),
  "FLASK_SECRET_KEY" => value.call(
    "FLASK_SECRET_KEY",
    "change-this-ui-secret"
  ),
  "GBIF_USER_AGENT" => value.call(
    "GBIF_USER_AGENT",
    "UkraineWildlifeTrainingApp/5.0"
  )
}

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.boot_timeout = 600

  config.vm.provider "virtualbox" do |vb|
    vb.gui = false
    vb.cpus = 1
  end

  machines.each do |name, machine_settings|
    config.vm.define name do |machine|
      machine.vm.hostname = "wildlife-#{name}"

      network_options = {
        ip: machine_settings[:ip],
        netmask: lan_netmask
      }
      if bridge_name && !bridge_name.empty?
        network_options[:bridge] = bridge_name
      end
      machine.vm.network "public_network", **network_options

      machine.vm.provider "virtualbox" do |vb|
        vb.name = "wildlife-v5-#{name}"
        vb.memory = machine_settings[:memory]
      end

      machine.vm.provision(
        "shell",
        path: "provision/node.sh",
        args: [name],
        env: provision_environment
      )
    end
  end
end
