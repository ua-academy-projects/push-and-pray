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

Після заміни example project ID, AMI, SSH key, email і secret IDs запускайте:

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

## Managed або self-managed PostgreSQL

`manage_db=false` залишає VM з `role=database` і контейнерним PostgreSQL.
`manage_db=true` прибирає database VM та створює RDS або Cloud SQL відповідно
до `database.cloud`.

Ansible отримує provider-neutral output `managed_database`, перевіряє TCP
доступ з workload VM і запускає міграції з History VM. `DATABASE_HOST`, port,
name, user та sslmode більше не залежать від inventory group `database`.

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
private routes. Cloud SQL peering імпортує та експортує custom routes.

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
