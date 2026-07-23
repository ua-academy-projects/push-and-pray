{ pkgs, lib, config, ... }:

{
  packages = [
    pkgs.postgresql
    pkgs.zlib
    pkgs.stdenv.cc.cc.lib
    pkgs.docker-compose
  ];
  # ---------------------------------------------------------------------
  # Python
  # ---------------------------------------------------------------------
  languages.python = {
    enable = true;
    version = "3.12";
    venv = {
      enable = true;
      requirements = ./requirements-dev.txt;
    };
  };

  # ---------------------------------------------------------------------
  # PostgreSQL (локальний сервер, піднімається разом з `devenv up`)
  # ---------------------------------------------------------------------
  services.postgres = {
    enable = true;
    listen_addresses = "127.0.0.1";
    port = 5432;
    initialDatabases = [
      { name = "taska-db"; }
    ];
    # Створюємо роль devops, яку очікують сервіси за замовчуванням
    # (див. backend/backend.py -> DB_CONFIG).
    initialScript = ''
      CREATE ROLE admin WITH LOGIN PASSWORD 'admin' SUPERUSER;
      GRANT ALL PRIVILEGES ON DATABASE taska-db TO admin;
    '';
  };

  # ---------------------------------------------------------------------
  # Змінні середовища для трьох сервісів
  # ---------------------------------------------------------------------
  env.DB_HOST = "localhost";
  env.DB_PORT = "5432";
  env.DB_NAME = "taska-db";
  env.DB_USER = "admin";
  env.DB_PASSWORD = "admin";
  env.WATCHED_CITIES = "Kyiv,Warsaw,Berlin";
  env.POLL_INTERVAL_SECONDS = "900";

  env.BACKEND_SERVICE_URL = "http://localhost:5002";
  env.PROXY_SERVICE_URL = "http://localhost:5001";
  env.LD_LIBRARY_PATH = lib.makeLibraryPath [
    pkgs.zlib
    pkgs.stdenv.cc.cc.lib
  ];
  # ---------------------------------------------------------------------
  # Процеси - `devenv up` запускає всі три сервіси одночасно
  # (поруч із PostgreSQL, який теж є процесом devenv)
  # ---------------------------------------------------------------------
  processes = {
    backend-service.exec = "cd backend && python backend.py";
    proxy-service.exec = "cd proxy && python proxy.py";
    ui-service.exec = "cd ui-service && python ui.py";
    poller-service.exec = "cd poller-service && python poller.py";
  };

  # ---------------------------------------------------------------------
  # Корисні команди в shell (напр. `devenv shell` -> `psql-app`)
  # ---------------------------------------------------------------------
  scripts.psql-app.exec = ''
    psql -h localhost -U admin -d taska-db "$@"
  '';

  enterShell = ''
    echo "DevOps Academy dev environment"
    echo "  python:     $(python --version)"
    echo "  postgres:   $(pg_ctl --version)"
    echo ""
    echo "Команди:"
    echo "  devenv up        - запустити postgres + всі 3 сервіси"
    echo "  psql-app         - підключитись до БД devops_academy"
  '';
}
