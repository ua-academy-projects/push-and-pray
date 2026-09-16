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
          };
        in
        {
          default = assert nixpkgs.lib.hasPrefix "1.16." pkgs.terraform.version;
            pkgs.mkShell {
              packages = with pkgs; [
                ansible
                ansible-lint
                awscli2
                check-jsonschema
                git
                google-cloud-sdk
                jq
                openssl
                python3Packages.boto3
                python3Packages.botocore
                python3Packages.google-auth
                python3Packages.requests
                shellcheck
                terraform
              ];

              shellHook = ''
                export OILSCOPE_PROJECT_CONFIG="''${OILSCOPE_PROJECT_CONFIG:-$HOME/dev.json}"
                export TF_VAR_project_config_path="''${TF_VAR_project_config_path:-$OILSCOPE_PROJECT_CONFIG}"
                export GOOGLE_APPLICATION_CREDENTIALS="''${GOOGLE_APPLICATION_CREDENTIALS:-$HOME/.config/gcp/oil-project/terraform-sa.json}"
                export AWS_PROFILE="''${AWS_PROFILE:-terraform}"
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
