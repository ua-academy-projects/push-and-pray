{
  description = "OilScope infrastructure development shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [ "terraform" ];
            overlays = [
              (final: prev: {
                python3 = prev.python3.override {
                  packageOverrides = pyFinal: pyPrev: {
                    # azure.azcollection 3.21 imports the legacy
                    # ``activestamp`` module, removed by SDK 11.x.
                    "azure-mgmt-recoveryservicesbackup" = pyPrev."azure-mgmt-recoveryservicesbackup".overridePythonAttrs (old: {
                      version = "9.1.0";
                      pyproject = null;
                      format = "setuptools";
                      src = prev.fetchurl {
                        url = "https://files.pythonhosted.org/packages/d1/10/e3d49f12842a84de410f8ed9831d6dcf6ee04e993f79fe4eb33adf1a9265/azure-mgmt-recoveryservicesbackup-9.1.0.tar.gz";
                        hash = "sha256-Hp/UBsDJ7iYn9aNx8BL4dzQvf8bzOyVk/NFNbwZjzQ8=";
                      };
                    });
                    "azure-mgmt-resourcehealth" = pyPrev.buildPythonPackage {
                      pname = "azure-mgmt-resourcehealth";
                      version = "1.0.0b6";
                      pyproject = null;
                      format = "setuptools";
                      src = prev.fetchurl {
                        url = "https://files.pythonhosted.org/packages/2f/bc/512a48904416d0a142ab147f029d3b185730796bbbd4bddfc3f7649aa8b5/azure_mgmt_resourcehealth-1.0.0b6.tar.gz";
                        hash = "sha256-ApGd4cj5kmAI3tO/h9RBw6HNhornRdpUMcQD01Pgrm4=";
                      };
                      dependencies = with pyFinal; [
                        azure-common
                        azure-mgmt-core
                        isodate
                        typing-extensions
                      ];
                      doCheck = false;
                    };
                  };
                };
              })
            ];
          };
          ansibleWithCloudSdk = pkgs.python3.withPackages (ps: with ps; [
            ansible
            boto3
            botocore
            google-auth
            requests
            azure-identity
            azure-mgmt-authorization
            azure-mgmt-automation
            azure-mgmt-batch
            azure-mgmt-cdn
            azure-mgmt-cognitiveservices
            azure-mgmt-compute
            azure-mgmt-containerinstance
            azure-mgmt-containerregistry
            azure-mgmt-containerservice
            azure-mgmt-core
            azure-mgmt-datafactory
            azure-mgmt-databricks
            azure-mgmt-dns
            azure-mgmt-eventhub
            azure-mgmt-hybridcompute
            azure-mgmt-iothub
            azure-mgmt-loganalytics
            azure-mgmt-managementgroups
            azure-mgmt-marketplaceordering
            azure-mgmt-monitor
            azure-mgmt-mysqlflexibleservers
            azure-mgmt-network
            azure-mgmt-notificationhubs
            azure-mgmt-postgresqlflexibleservers
            azure-mgmt-privatedns
            azure-mgmt-rdbms
            azure-mgmt-recoveryservicesbackup
            azure-mgmt-resource
            ps."azure-mgmt-resourcehealth"
            azure-mgmt-search
            azure-mgmt-servicebus
            azure-mgmt-sql
            azure-mgmt-storage
            azure-mgmt-trafficmanager
            azure-mgmt-web
            azure-storage-blob
            azure-storage-file-share
            microsoft-kiota-authentication-azure
            msgraph-core
            msgraph-sdk
            msrest
            msrestazure
          ]);
        in
        {
          default = assert nixpkgs.lib.hasPrefix "1.16." pkgs.terraform.version;
            pkgs.mkShell {
              packages = with pkgs; [
                ansibleWithCloudSdk
                ansible-lint
                awscli2
                azure-cli
                check-jsonschema
                git
                (google-cloud-sdk.withExtraComponents [
                  google-cloud-sdk.components.gke-gcloud-auth-plugin
                ])
                jq
                kubectl
                kubernetes-helm
                openssl
                python3Packages.virtualenv
                shellcheck
                terraform
                azure-cli
              ];

              shellHook = ''
                export OILSCOPE_PROJECT_CONFIG="''${OILSCOPE_PROJECT_CONFIG:-$HOME/dev.json}"
                export TF_VAR_project_config_path="''${TF_VAR_project_config_path:-$OILSCOPE_PROJECT_CONFIG}"
                export GOOGLE_APPLICATION_CREDENTIALS="''${GOOGLE_APPLICATION_CREDENTIALS:-$HOME/.config/gcp/oil-project/terraform-sa.json}"
                export AWS_PROFILE="''${AWS_PROFILE:-terraform}"
                if [[ -z "''${ARM_SUBSCRIPTION_ID:-}" ]] && command -v az >/dev/null 2>&1; then
                  export ARM_SUBSCRIPTION_ID="$(az account show --query id --output tsv 2>/dev/null || true)"
                fi
                export OILSCOPE_SSH_KEY="''${OILSCOPE_SSH_KEY:-$HOME/.ssh/gcp_academy}"
                if [[ -z "''${OILSCOPE_SSH_USER:-}" && -f "$OILSCOPE_PROJECT_CONFIG" ]]; then
                  export OILSCOPE_SSH_USER="$(jq -r '.ssh_users | keys[0]' "$OILSCOPE_PROJECT_CONFIG")"
                fi

                ansible-setup() {
                  ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
                  (
                    cd infrastructure/ansible/oilscope/platform
                    ansible-galaxy collection build --force
                    ansible-galaxy collection install oilscope-platform-*.tar.gz --force
                  )
                }

                echo "Terraform $(terraform version | head -n1)"
                echo "Project config: $OILSCOPE_PROJECT_CONFIG"
                echo "After configuring the bastion, run: unset OILSCOPE_BASTION_CONNECT_PORT"
              '';
            };
        });
    };
}
