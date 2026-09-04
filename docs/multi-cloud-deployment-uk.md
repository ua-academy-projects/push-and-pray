# Розгортання OilScope у GCP та AWS

## Один конфіг

Terraform і Ansible читають один project-config.json. Поле default_cloud
визначає хмару всіх VM без власного override. Щоб перенести одну VM, додайте
до неї поле cloud зі значенням aws або gcp.

VM містять тільки абстрактні machine_profile, image_profile та boot_disk.profile.
Реальні region, zone, machine type, disk type й image/AMI знаходяться у
словниках clouds.gcp і clouds.aws. Вкладені модулі modules/gcp/config і
modules/aws/config фільтрують VM, застосовують defaults та виконують lookup для
своєї хмари. Усі network, VM та config-підмодулі розташовані всередині
modules/gcp або modules/aws. Root module не виконує конвертацію.

## Межа mixed-cloud

Кожна хмара отримує власну мережу. VPN, peering і cross-cloud routes не
створюються. Private workload керується через bastion у тій самій хмарі.
Якщо в хмарі є private workload, але немає її bastion, Terraform може створити
VM, однак Ansible SSH до неї не матиме маршруту.

## Підготовка

Без AWS досвіду спочатку вручну створіть і видаліть у Console тестові VPC,
subnet, security group та EC2 instance. Не зберігайте AWS access keys, private
SSH keys або secret values у JSON.

    cp project-config.example.json project-config.local.json
    chmod 600 project-config.local.json

Заповніть provider catalogs. AWS AMI залежить від region, тому замініть example
AMI на чинний ID у вибраному region. Для перемикання всього deployment змініть
тільки default_cloud.

## Статична перевірка

    uvx check-jsonschema \
      --schemafile infrastructure/terraform/project-config.schema.json \
      project-config.local.json
    terraform -chdir=infrastructure/terraform fmt -check -recursive
    terraform -chdir=infrastructure/terraform init -backend=false
    terraform -chdir=infrastructure/terraform validate
    terraform -chdir=infrastructure/terraform test

Ці команди не доводять доступність credentials, quota, AMI або реальний
deployment.

## Terraform state

Terraform backend не можна перемикати variable або lookup. У root збережено
існуючий GCS backend. Не застосовуйте різні environments до одного state.
AWS-only production backend або migration state є окремою операцією, а не
частиною default_cloud.

## Plan і bootstrap

Перед plan перевірте identity командами aws sts get-caller-identity та
gcloud auth application-default print-access-token.

    terraform -chdir=infrastructure/terraform plan \
      -var=project_config_path="$(pwd)/project-config.local.json"

Новий bastion спочатку слухає port 22. Перший apply виконайте з
enable_bastion_ssh_bootstrap=true. Після виконання bastion role повторіть apply
без цього flag, щоб видалити temporary firewall/security-group rule.

## Ansible

    pip install -r infrastructure/ansible/requirements.txt
    ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
    export OILSCOPE_PROJECT_CONFIG="$(pwd)/project-config.local.json"
    ansible-inventory -i infrastructure/ansible/inventory/oilscope.yml --graph

Inventory plugin запускає тільки потрібні delegates: google.cloud.gcp_compute
та/або amazon.aws.aws_ec2. Discovery використовує application, environment і
cloud labels/tags. SSH key задається OILSCOPE_SSH_KEY або окремо
OILSCOPE_GCP_SSH_KEY та OILSCOPE_AWS_SSH_KEY.

## Secrets

GCP використовує Secret Manager, AWS — SSM Parameter Store Standard
SecureString. Secret payload не передається Terraform. Upload role створює
окрему target для кожної пари cloud/secret_id. Resolve role вибирає backend
через host variable oilscope_cloud.

## Вартість і доказ результату

free_tier_guardrails не гарантує нульовий рахунок. Перевіряйте account age,
credits, aggregate VM hours, public IPv4, region і Billing dashboard. П'ять
постійних VM зазвичай не вміщуються у безкоштовну квоту одного VM-month.

Live apply і destroy запускаються тільки після перевірки точного account,
project, region та state. fmt, validate й mock tests не є доказом
end-to-end deployment.
