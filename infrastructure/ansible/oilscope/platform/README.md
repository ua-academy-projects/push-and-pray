# Ansible Collection — oilscope.platform

Validate a config:

    uvx check-jsonschema \
      --schemafile infrastructure/terraform/project-config.schema.json \
      /absolute/path/project-config.json

Build and install this collection after plugin or role changes, then use:

    export OILSCOPE_PROJECT_CONFIG=/absolute/path/project-config.json
    ansible-inventory -i infrastructure/ansible/inventory/oilscope.yml --graph

Deploy workloads in Database, History, Fetcher, UI order:

    ansible-playbook oilscope.platform.deploy_workloads \
      -i infrastructure/ansible/inventory/oilscope.yml \
      -e project_config_path="$OILSCOPE_PROJECT_CONFIG"

A private workload requires a bastion in the same cloud. Cross-cloud
networking is outside this collection's scope.
