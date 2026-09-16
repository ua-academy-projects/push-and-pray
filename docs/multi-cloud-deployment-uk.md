# Розгортання OilScope у GCP та AWS

## Три профілі, один контракт

Terraform і Ansible читають один JSON-контракт. Готові профілі:

- `configs/project-config.aws.json`;
- `configs/project-config.gcp.json`;
- `configs/project-config.mixed.json`.

`default_cloud` визначає хмару VM без власного `cloud`. Абстрактні
`machine_profile`, `image_profile` і `boot_disk.profile` перетворюються на
provider values у спільному `modules/config`.

## Команди

Після перевірки account/project, AMI, SSH key, email і створення всіх secret IDs
запускайте:

    ./scripts/deploy-cloud.sh aws
    ./scripts/deploy-cloud.sh gcp
    ./scripts/deploy-cloud.sh mixed

Явний шлях також підтримується:

    ./scripts/deploy-cloud.sh ./project-config.json

AWS і GCP мають ізольовані Terraform roots у
`infrastructure/terraform/stacks`. Mixed використовує головний root. Local
state зберігається окремо в
`infrastructure/terraform/.state/<profile>.tfstate`. Для production замініть
local backend на окремі remote backend keys.

## Два режими даних, черги та сесій

`manage_db=false` залишає VM з `role=database` і контейнерним PostgreSQL.
Образ PostgreSQL/migrations береться з GitHub Container Registry (GHCR).
Черга подій і UI-сесії також зберігаються у PostgreSQL, тому Redis та RabbitMQ
у цьому режимі не запускаються.

`manage_db=true` прибирає database VM та створює RDS або Cloud SQL відповідно
до `database.cloud`. У цьому режимі History VM додатково запускає RabbitMQ для
черги та Redis для UI-сесій. Їхні persistent Docker volumes залишаються на
History VM.

Ansible отримує provider-neutral output `managed_database`, перевіряє TCP
доступ з workload VM і запускає міграції з History VM. `DATABASE_HOST`, port,
name, user та sslmode більше не залежать від inventory group `database`.

## Redis і RabbitMQ у cloud registry

Для `manage_db=true` Terraform створює окремі приватні repositories:

- AWS Elastic Container Registry для AWS workloads;
- GCP Artifact Registry для GCP workloads.

`deploy-cloud.sh` бере upstream-образи з `managed_services`, копіює їхні
multi-architecture manifests через `docker buildx imagetools create` у registry
кожної задіяної хмари, а History VM завантажує їх через власну IAM role або
service account. Паролі `RABBITMQ_PASSWORD` і `REDIS_PASSWORD` надходять лише із
SSM Parameter Store або Secret Manager. Для mirroring локально потрібні Docker
Buildx і відповідно `aws` та/або `gcloud` з активною автентифікацією.

RabbitMQ (`5672`) дозволений тільки від Fetcher, Redis (`6379`) — від UI;
у mixed-профілі доступ із другої хмари йде приватним VPN-маршрутом. Порти не
публікуються через public security/firewall rules.

Початкові dev-профілі мають:

    "backups_enabled": false,
    "backup_on_delete": false,
    "deletion_protection": false

Для RDS це означає `backup_retention_period=0`, `skip_final_snapshot=true` і
`delete_automated_backups=true`. Для Cloud SQL вимкнені regular/PITR та final
backup. Видалення такої БД може спричинити повну втрату даних.

## Приватна мережа БД

RDS використовує DB subnet group з двома private subnets у різних Availability
Zones, `publicly_accessible=false` і security group без `0.0.0.0/0` ingress.
Застосунки підключаються до DNS endpoint.

Cloud SQL використовує окремий Private Services Access range,
`google_service_networking_connection` та `ipv4_enabled=false`. Це service
producer range, а не звичайна VM subnet.

Mixed profile має різні AWS/GCP VPC CIDR. Terraform створює AWS Virtual Private
Gateway, Customer Gateway, Site-to-Site VPN, GCP Classic VPN tunnel і тільки
private routes. Cloud SQL peering імпортує та експортує custom routes. Для RDS
database subnets мають окрему private route table з маршрутом назад до GCP через
Virtual Private Gateway. Жоден managed database не має public IP.

## Моніторинг і поштові сповіщення

Коли `observability.enabled=true`, AWS створює CloudWatch dashboard, EC2/RDS
alarms, log metric для HTTP 500, synthetic HTTPS check, SNS topic і budget
notifications. GCP створює Monitoring dashboard, VM/Cloud SQL alert policies,
uptime check, logs-based HTTP 500 metric і email notification channel. Агенти на
VM читають `/var/lib/docker/containers/*/*.log`, тобто саме application logs, а
не лише журнал Docker daemon.

У готових cloud-профілях одержувач — `o.m.zakip@gmail.com`. Після першого AWS
apply потрібно підтвердити SNS email subscription; до підтвердження CloudWatch
alarms не надсилатимуть листи. Terraform-тести перевіряють конфігурацію, але
фактичну доставку листа можна підтвердити тільки після live deployment і
навмисно згенерованої тестової 500-відповіді.

Поточний mixed VPN має один IPsec tunnel і не є HA. Для production додайте
другий tunnel та dynamic routing через Cloud Router/BGP або GCP HA VPN.

## Щомісячний restore та ім'я

Managed instance називається:

    <name_prefix>-<environment>-postgres-<generation>

Для нового restore змініть `generation`, наприклад `2026-09` на `2026-10`, і
задайте одне з полів:

- `restore.aws_snapshot_identifier`;
- `restore.gcp_backup_run_id`.

Без restore source нове ім'я створить порожню БД. Пароль у secret backend має
відповідати паролю snapshot/backup. Перевірте plan, створіть нову БД, перевірте
міграції та HTTPS і лише потім видаляйте стару.

Не використовуйте `timestamp()` або random suffix для `generation`: це
спричинить небажану заміну на наступному plan.

## Dynamic blocks

Cloud SQL module використовує dynamic blocks для backup configuration, final
backup configuration та optional restore context. Повторювані subnets, routes
і security rules створюються через `for_each`.

## Secrets

Secret IDs зберігаються в JSON, значення — в GCP Secret Manager або AWS SSM
Parameter Store. `database.password_secret_id` визначає спільний password
container для managed DB та workloads. Deployment environment variable
утворюється з цього ID у верхньому регістрі, наприклад
`example-db-password` → `EXAMPLE_DB_PASSWORD`. Provider змушений зберегти
password managed instance як sensitive state value, тому state повинен бути
зашифрований і доступний лише deployment principals.

## Статична перевірка

    uvx check-jsonschema \
      --schemafile infrastructure/terraform/project-config.schema.json \
      project-config.example.json configs/*.json
    terraform -chdir=infrastructure/terraform fmt -check -recursive
    terraform -chdir=infrastructure/terraform validate
    terraform -chdir=infrastructure/terraform test
    terraform -chdir=infrastructure/terraform/stacks/aws test
    terraform -chdir=infrastructure/terraform/stacks/gcp test

Перед live apply окремо перевірте `aws sts get-caller-identity` та
`gcloud auth application-default print-access-token`. `fmt`, `validate` і mock
tests не доводять quota, реальну VPN connectivity, SSH, migrations або HTTPS.

RDS, Cloud SQL, public IPv4 і VPN є платними ресурсами. `free_tier_guardrails`
не гарантує нульовий рахунок.
