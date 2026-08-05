require "fileutils"
require "uri"

# Vagrant launches QEMU from a Ruby child process on macOS. Apple Objective-C
# fork safety can abort that child before QEMU starts; this is safe here because
# the child immediately execs the isolated QEMU process.
ENV["OBJC_DISABLE_INITIALIZE_FORK_SAFETY"] ||= "YES" if RUBY_PLATFORM.include?("darwin")
# macOS vmnet-bridged QEMU guests are started reliably one at a time. Vagrant
# otherwise batches all six machines and can make each daemonized QEMU process
# exit with no useful stderr.
ENV["VAGRANT_NO_PARALLEL"] ||= "1"

GENERATED_DIR = "infra/vagrant/generated"
ENV_FILE = ".env"
LOCAL_ENV_FILE = ".env.vagrant.local"

abort "File #{ENV_FILE} was not found" unless File.file?(ENV_FILE)

def read_dotenv(path)
  return {} unless File.file?(path)

  File.readlines(path, chomp: true).each_with_object({}) do |line, values|
    line = line.strip
    next if line.empty? || line.start_with?("#")

    name, value = line.split("=", 2)
    abort "Invalid line in #{path}: #{line}" unless name && value

    values[name] = value
  end
end

DOTENV = read_dotenv(ENV_FILE).merge(read_dotenv(LOCAL_ENV_FILE)).freeze

def env(name, default = nil)
  value = ENV.fetch(name, DOTENV.fetch(name, default))
  abort "Add #{name} to .env" if value.nil? || value.empty?

  value
end

def optional_env(name)
  ENV.fetch(name, DOTENV.fetch(name, ""))
end

BOX = env("RATEBOARD_VAGRANT_BOX", "perk/ubuntu-2204-arm64")
UI_PORT = env("UI_PORT")
API_FETCHER_PORT = env("API_FETCHER_PORT")
BACKEND_SERVICE_PORT = env("BACKEND_SERVICE_PORT")
VMNET_INTERFACE = env("RATEBOARD_VMNET_INTERFACE", "en0")
NETWORK_MODE = env("RATEBOARD_NETWORK_MODE", "vmnet_bridged")
abort "RATEBOARD_NETWORK_MODE must be vmnet_bridged" unless NETWORK_MODE == "vmnet_bridged"

MACHINES = {
  "logs"            => { ip: env("RATEBOARD_LOGS_IP", "192.168.0.226"), ssh_port: 50_226, memory: "2G" },
  "database"        => { ip: env("RATEBOARD_DATABASE_IP", "192.168.0.224"), ssh_port: 50_224 },
  "rabbitmq"        => { ip: env("RATEBOARD_RABBITMQ_IP", "192.168.0.225"), ssh_port: 50_225 },
  "backend-service" => { ip: env("RATEBOARD_BACKEND_SERVICE_IP", "192.168.0.223"), ssh_port: 50_223 },
  "api-fetcher"     => { ip: env("RATEBOARD_API_FETCHER_IP", "192.168.0.222"), ssh_port: 50_222 },
  "ui"              => { ip: env("RATEBOARD_UI_IP", "192.168.0.221"), ssh_port: 50_221 }
}.freeze

abort "Every RATEBOARD_*_IP must be unique" unless
  MACHINES.values.map { |machine| machine[:ip] }.uniq.length == MACHINES.length

INTERNAL_TOKEN = optional_env("RATEBOARD_INTERNAL_API_TOKEN")
INTERNAL_TOKEN = optional_env("RATEBOARD_BACKEND_SERVICE_TOKEN") if INTERNAL_TOKEN.empty?
INTERNAL_TOKEN = optional_env("INTERNAL_API_TOKEN") if INTERNAL_TOKEN.empty?
INTERNAL_TOKEN = env("BACKEND_SERVICE_TOKEN") if INTERNAL_TOKEN.empty?
DATABASE_URI = URI.parse(env("DATABASE_URL"))
RABBITMQ_URI = URI.parse(env("RABBITMQ_URL"))

DB_PASSWORD = optional_env("RATEBOARD_DB_PASSWORD")
DB_PASSWORD = URI.decode_www_form_component(DATABASE_URI.password.to_s) if DB_PASSWORD.empty?
RABBITMQ_PASSWORD = optional_env("RATEBOARD_RABBITMQ_PASSWORD")
RABBITMQ_USER = optional_env("RATEBOARD_RABBITMQ_USER")
RABBITMQ_VHOST = optional_env("RATEBOARD_RABBITMQ_VHOST")
if RABBITMQ_USER.empty?
  RABBITMQ_USER = RABBITMQ_PASSWORD.empty? ?
    URI.decode_www_form_component(RABBITMQ_URI.user.to_s) :
    "rateboard"
end
RABBITMQ_PASSWORD = URI.decode_www_form_component(RABBITMQ_URI.password.to_s) if RABBITMQ_PASSWORD.empty?
if RABBITMQ_VHOST.empty?
  rabbitmq_url_path = RABBITMQ_URI.path.empty? ? "/" : RABBITMQ_URI.path
  RABBITMQ_VHOST = URI.decode_www_form_component(rabbitmq_url_path.delete_prefix("/"))
  RABBITMQ_VHOST = "/" if RABBITMQ_VHOST.empty?
end
REDIS_PASSWORD = optional_env("RATEBOARD_REDIS_PASSWORD")
SSH_USERNAME = env("RATEBOARD_SSH_USERNAME", "admin")
SSH_PUBLIC_KEY_FILES = env("RATEBOARD_SSH_PUBLIC_KEY_FILES").split(",").map(&:strip).reject(&:empty?).freeze
SSH_IDENTITY_FILE = env("RATEBOARD_SSH_IDENTITY_FILE")
LOGS_INGEST_USER = env("RATEBOARD_LOGS_INGEST_USER", "rateboard_alloy")
LOGS_INGEST_PASSWORD = env("RATEBOARD_LOGS_INGEST_PASSWORD")
GRAFANA_ADMIN_USER = env("GRAFANA_ADMIN_USER", "admin")
GRAFANA_ADMIN_PASSWORD = env("GRAFANA_ADMIN_PASSWORD")
LOGS_RETENTION = env("RATEBOARD_LOGS_RETENTION", "336h")

abort "DATABASE_URL must contain a password" if DB_PASSWORD.empty?
abort "RABBITMQ_URL must contain a username and password" if
  RABBITMQ_USER.empty? || RABBITMQ_PASSWORD.empty?
abort "Add RATEBOARD_REDIS_PASSWORD to .env.vagrant.local" if REDIS_PASSWORD.empty?
abort "RATEBOARD_REDIS_PASSWORD must not contain line breaks" if REDIS_PASSWORD.match?(/[\r\n]/)
abort "RATEBOARD_SSH_USERNAME must be a valid Linux username" unless SSH_USERNAME.match?(/\A[a-z_][a-z0-9_-]{0,31}\z/)
abort "RATEBOARD_SSH_IDENTITY_FILE must be an absolute path" unless SSH_IDENTITY_FILE.start_with?("/")
abort "RATEBOARD_LOGS_RETENTION must be expressed in hours, for example 336h" unless LOGS_RETENTION.match?(/\A[1-9][0-9]*h\z/)

SAFE_SECRET = /\A[A-Za-z0-9._~-]+\z/
{
  "INTERNAL_API_TOKEN" => INTERNAL_TOKEN,
  "DATABASE_URL password" => DB_PASSWORD,
  "RABBITMQ user" => RABBITMQ_USER,
  "RABBITMQ_URL password" => RABBITMQ_PASSWORD,
  "RATEBOARD_LOGS_INGEST_USER" => LOGS_INGEST_USER,
  "RATEBOARD_LOGS_INGEST_PASSWORD" => LOGS_INGEST_PASSWORD,
  "GRAFANA_ADMIN_USER" => GRAFANA_ADMIN_USER,
  "GRAFANA_ADMIN_PASSWORD" => GRAFANA_ADMIN_PASSWORD
}.each do |name, value|
  abort "#{name} contains unsupported characters" unless SAFE_SECRET.match?(value)
end
abort "Replace RATEBOARD_LOGS_INGEST_PASSWORD in .env.vagrant.local" if LOGS_INGEST_PASSWORD.start_with?("replace-with-")
abort "Replace GRAFANA_ADMIN_PASSWORD in .env.vagrant.local" if GRAFANA_ADMIN_PASSWORD.start_with?("replace-with-")

DATABASE_URI.host = "rates-db"
DATABASE_URI.port ||= 5432
DATABASE_URI.password = DB_PASSWORD
RABBITMQ_PASSWORD_ESCAPED = URI.encode_www_form_component(RABBITMQ_PASSWORD)
RABBITMQ_VHOST_PATH = RABBITMQ_VHOST == "/" ? "/" : "/#{URI.encode_www_form_component(RABBITMQ_VHOST)}"

FileUtils.mkdir_p(GENERATED_DIR)
AUTHORIZED_KEYS_PATH = File.join(GENERATED_DIR, "authorized_keys")
authorized_keys = SSH_PUBLIC_KEY_FILES.flat_map do |path|
  expanded_path = File.expand_path(path)
  abort "SSH public key must use an absolute path: #{path}" unless expanded_path == path
  abort "SSH public key was not found: #{path}" unless File.file?(path)
  abort "Invalid SSH public key: #{path}" unless system("ssh-keygen", "-l", "-f", path, out: File::NULL, err: File::NULL)

  File.readlines(path, chomp: true).map(&:strip).reject(&:empty?)
end.uniq
abort "RATEBOARD_SSH_PUBLIC_KEY_FILES did not contain a public key" if authorized_keys.empty?
File.write(AUTHORIZED_KEYS_PATH, authorized_keys.join("\n") + "\n")
File.chmod(0o600, AUTHORIZED_KEYS_PATH)

DATABASE_STORAGE_DIR = File.expand_path(".vagrant-data/database", __dir__)
DATABASE_DISK_PATH = File.join(DATABASE_STORAGE_DIR, "postgresql.qcow2")
DATABASE_DISK_SIZE = env("RATEBOARD_DATABASE_DISK_SIZE", "20G")
FileUtils.mkdir_p(DATABASE_STORAGE_DIR)
unless File.file?(DATABASE_DISK_PATH)
  abort "qemu-img is required to create #{DATABASE_DISK_PATH}" unless system(
    "qemu-img", "create", "-q", "-f", "qcow2", DATABASE_DISK_PATH, DATABASE_DISK_SIZE
  )
  File.chmod(0o600, DATABASE_DISK_PATH)
end

LOGS_STORAGE_DIR = File.expand_path(".vagrant-data/logs", __dir__)
LOGS_DISK_PATH = File.join(LOGS_STORAGE_DIR, "loki.qcow2")
LOGS_DISK_SIZE = env("RATEBOARD_LOGS_DISK_SIZE", "10G")
FileUtils.mkdir_p(LOGS_STORAGE_DIR)
unless File.file?(LOGS_DISK_PATH)
  abort "qemu-img is required to create #{LOGS_DISK_PATH}" unless system(
    "qemu-img", "create", "-q", "-f", "qcow2", LOGS_DISK_PATH, LOGS_DISK_SIZE
  )
  File.chmod(0o600, LOGS_DISK_PATH)
end

LOGS_TLS_DIR = File.join(GENERATED_DIR, "logs-tls")
unless system(
  "bash", "scripts/generate-logs-tls.sh",
  MACHINES.fetch("logs")[:ip], LOGS_TLS_DIR,
  out: File::NULL
)
  abort "Failed to generate the Rateboard logs TLS certificate"
end

File.write("#{GENERATED_DIR}/ui.env", <<~ENV)
  UI_PUBLIC_HOST=rateboard.test
  UI_PUBLIC_IP=#{MACHINES.fetch("ui")[:ip]}
  HISTORY_SERVICE_URL=http://rates-backend-service:#{BACKEND_SERVICE_PORT}
ENV

File.write("#{GENERATED_DIR}/api-fetcher.env", <<~ENV)
  API_FETCHER_HOST=0.0.0.0
  API_FETCHER_PORT=#{API_FETCHER_PORT}
  INTERNAL_API_TOKEN=#{INTERNAL_TOKEN}
  RABBITMQ_ENABLED=#{env("RABBITMQ_ENABLED")}
  RABBITMQ_URL=amqp://#{RABBITMQ_USER}:#{RABBITMQ_PASSWORD_ESCAPED}@rates-rabbitmq:5672#{RABBITMQ_VHOST_PATH}
  RABBITMQ_EVENTS_EXCHANGE=#{env("RABBITMQ_EVENTS_EXCHANGE", "rates.events")}
  RABBITMQ_OBSERVATIONS_QUEUE=#{env("RABBITMQ_OBSERVATIONS_QUEUE", "rates.observations")}
  RABBITMQ_OBSERVATION_ROUTING_KEY=#{env("RABBITMQ_OBSERVATION_ROUTING_KEY", "observation.collected")}
  RABBITMQ_COMMANDS_EXCHANGE=#{env("RABBITMQ_COMMANDS_EXCHANGE", "rates.commands")}
  RABBITMQ_COMMANDS_QUEUE=#{env("RABBITMQ_COMMANDS_QUEUE", "rates.fetch.commands")}
  RABBITMQ_COMMAND_ROUTING_KEY=#{env("RABBITMQ_COMMAND_ROUTING_KEY", "backfill.requested")}
  COINGECKO_BASE_URL=#{env("COINGECKO_BASE_URL")}
  COINGECKO_API_KEY=#{optional_env("COINGECKO_API_KEY")}
  FRANKFURTER_BASE_URL=#{env("FRANKFURTER_BASE_URL")}
  COLLECTOR_ENABLED=#{env("COLLECTOR_ENABLED")}
  COLLECTOR_INTERVAL_SECONDS=#{env("COLLECTOR_INTERVAL_SECONDS")}
  LOG_LEVEL=#{env("LOG_LEVEL")}
ENV

File.write("#{GENERATED_DIR}/backend-service.env", <<~ENV)
  BACKEND_SERVICE_HOST=0.0.0.0
  BACKEND_SERVICE_PORT=#{BACKEND_SERVICE_PORT}
  DATABASE_URL=#{DATABASE_URI}
  RABBITMQ_ENABLED=#{env("RABBITMQ_ENABLED")}
  RABBITMQ_URL=amqp://#{RABBITMQ_USER}:#{RABBITMQ_PASSWORD_ESCAPED}@rates-rabbitmq:5672#{RABBITMQ_VHOST_PATH}
  RABBITMQ_EVENTS_EXCHANGE=#{env("RABBITMQ_EVENTS_EXCHANGE", "rates.events")}
  RABBITMQ_OBSERVATIONS_QUEUE=#{env("RABBITMQ_OBSERVATIONS_QUEUE", "rates.observations")}
  RABBITMQ_OBSERVATION_ROUTING_KEY=#{env("RABBITMQ_OBSERVATION_ROUTING_KEY", "observation.collected")}
  RABBITMQ_COMMANDS_EXCHANGE=#{env("RABBITMQ_COMMANDS_EXCHANGE", "rates.commands")}
  RABBITMQ_COMMANDS_QUEUE=#{env("RABBITMQ_COMMANDS_QUEUE", "rates.fetch.commands")}
  RABBITMQ_COMMAND_ROUTING_KEY=#{env("RABBITMQ_COMMAND_ROUTING_KEY", "backfill.requested")}
  STARTUP_BACKFILL_ENABLED=#{env("STARTUP_BACKFILL_ENABLED", "true")}
  STARTUP_BACKFILL_MAX_DAYS=#{env("STARTUP_BACKFILL_MAX_DAYS", "365")}
ENV

File.write("#{GENERATED_DIR}/database.env", <<~ENV)
  POSTGRES_DB=rates
  POSTGRES_USER=rates
  POSTGRES_PASSWORD=#{DB_PASSWORD}
ENV

File.write("#{GENERATED_DIR}/rabbitmq.env", <<~ENV)
  RABBITMQ_USER=#{RABBITMQ_USER}
  RABBITMQ_PASSWORD=#{RABBITMQ_PASSWORD}
  RABBITMQ_VHOST=#{RABBITMQ_VHOST}
  RABBITMQ_DEFAULT_USER=#{RABBITMQ_USER}
  RABBITMQ_DEFAULT_PASS=#{RABBITMQ_PASSWORD}
  RABBITMQ_DEFAULT_VHOST=#{RABBITMQ_VHOST}
  REDIS_PASSWORD=#{REDIS_PASSWORD}
ENV

File.write("#{GENERATED_DIR}/logs.env", <<~ENV)
  LOGS_PUBLIC_HOST=rates-logs
  LOGS_PUBLIC_IP=#{MACHINES.fetch("logs")[:ip]}
  RATEBOARD_LOGS_RETENTION=#{LOGS_RETENTION}
  RATEBOARD_LOGS_INGEST_USER=#{LOGS_INGEST_USER}
  RATEBOARD_LOGS_INGEST_PASSWORD=#{LOGS_INGEST_PASSWORD}
  GRAFANA_ADMIN_USER=#{GRAFANA_ADMIN_USER}
  GRAFANA_ADMIN_PASSWORD=#{GRAFANA_ADMIN_PASSWORD}
  GF_SERVER_DOMAIN=rates-logs
  GF_SERVER_ROOT_URL=https://rates-logs/
ENV

MACHINES.each do |name, machine|
  File.write("#{GENERATED_DIR}/#{name}-alloy.env", <<~ENV)
    RATEBOARD_VM_NAME=rates-#{name}
    RATEBOARD_VM_ROLE=#{name}
    RATEBOARD_ENVIRONMENT=vagrant
    RATEBOARD_LOGS_IP=#{MACHINES.fetch("logs")[:ip]}
    LOKI_PUSH_URL=https://rates-logs/loki/api/v1/push
    LOKI_INGEST_USER=#{LOGS_INGEST_USER}
    LOKI_INGEST_PASSWORD=#{LOGS_INGEST_PASSWORD}
  ENV
end

Dir.glob("#{GENERATED_DIR}/*.env").each { |file| File.chmod(0o600, file) }

HOSTS = <<~HOSTS
  #{MACHINES.fetch("ui")[:ip]} rates-ui rateboard.test
  #{MACHINES.fetch("api-fetcher")[:ip]} rates-api-fetcher
  #{MACHINES.fetch("backend-service")[:ip]} rates-backend-service
  #{MACHINES.fetch("database")[:ip]} rates-db
  #{MACHINES.fetch("rabbitmq")[:ip]} rates-rabbitmq
  #{MACHINES.fetch("logs")[:ip]} rates-logs
HOSTS

Vagrant.configure("2") do |config|
  config.vm.box = BOX

  config.vm.synced_folder ".", "/vagrant", type: "rsync",
    rsync__exclude: [
      ".git/", ".vagrant/", ".vagrant-data/", ".env*",
      "infra/vagrant/generated/", "api-fetcher/.venv/"
    ]

  MACHINES.each do |name, machine|
    config.vm.define name do |vm|
      vm.vm.hostname = "rates-#{name}"
      # vagrant-qemu 0.6.x uses this declaration for its second NIC. The QEMU
      # provider settings below attach that NIC to the physical LAN, not to a
      # host-only/private subnet.
      vm.vm.network "private_network", ip: machine[:ip]

      vm.vm.provider "qemu" do |qemu|
        qemu.memory = machine.fetch(:memory, "512M")
        qemu.smp = "2"

        qemu.ssh_port = machine[:ssh_port]
        # QEMU's macOS -daemonize path forks through Objective-C and can exit
        # before emitting stderr (notably with Homebrew QEMU 11.x). The
        # provider supports a detached non-daemonized launch that avoids this
        # failure while still managing the VM through its pid/control files.
        qemu.no_daemonize = true if RUBY_PLATFORM.include?("darwin")

        qemu.advanced_network = true
        qemu.net_mode = :vmnet_bridged
        qemu.vmnet_interface = VMNET_INTERFACE

        # vagrant-qemu 0.6.x supports extra QEMU drives. Keep PostgreSQL on a
        # host-side qcow2 outside .vagrant so container/VM recreation does not
        # delete database state. The database provisioner formats only a blank
        # disk and mounts an existing filesystem unchanged. Give the disk a
        # stable serial because /dev/vdb may be occupied by QEMU's cloud-init
        # seed disk.
        if name == "database"
          qemu.extra_qemu_args = [
            "-drive",
            "if=none,id=rateboard_pgdata,format=qcow2,file=#{DATABASE_DISK_PATH}",
            "-device",
            "virtio-blk-pci,drive=rateboard_pgdata,serial=rateboard-pgdata"
          ]
        elsif name == "logs"
          qemu.extra_qemu_args = [
            "-drive",
            "if=none,id=rateboard_logsdata,format=qcow2,file=#{LOGS_DISK_PATH}",
            "-device",
            "virtio-blk-pci,drive=rateboard_logsdata,serial=rateboard-logsdata"
          ]
        end
      end

      vm.vm.provision "file",
        source: AUTHORIZED_KEYS_PATH,
        destination: "/tmp/rateboard-authorized-keys"

      vm.vm.provision "file",
        source: "#{GENERATED_DIR}/#{name}-alloy.env",
        destination: "/tmp/rateboard-alloy.env"

      vm.vm.provision "file",
        source: "#{LOGS_TLS_DIR}/ca.crt",
        destination: "/tmp/rateboard-logs-ca.crt"

      if name == "logs"
        vm.vm.provision "file",
          source: "#{LOGS_TLS_DIR}/server.crt",
          destination: "/tmp/rateboard-logs-server.crt"
        vm.vm.provision "file",
          source: "#{LOGS_TLS_DIR}/server.key",
          destination: "/tmp/rateboard-logs-server.key"
      end

      vm.vm.provision "shell",
        path: "infra/vagrant/provision/common.sh",
        args: [HOSTS.gsub("\n", "\\n"), SSH_USERNAME]

      vm.vm.provision "file",
        source: "#{GENERATED_DIR}/#{name}.env",
        destination: "/tmp/rateboard.env"

      vm.vm.provision "shell",
        path: "infra/vagrant/provision/#{name}.sh"
    end
  end
end
