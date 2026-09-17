# Міграція на project-config schema version 1

## 1. Не змінюйте live state навмання

Збережіть копію config і state metadata, перевірте active account/project та
порівняйте Terraform state з provider APIs. Старі локальні state-файли можуть
бути stale; їх наявність не доводить, що ресурс існує. Не запускайте apply,
import або state removal до resource-by-resource звірки.

## 2. Оновіть selectors

| Старе поле | Version 1 |
| --- | --- |
| `default_cloud: aws|gcp` | `cloud_provider: aws|gcp` |
| `manage_db: false` | `data_profile: portable` |
| `manage_db: true` | `data_profile: managed` |
| відсутній runtime | `deployment_runtime: compose` |
| VM `cloud` | прибрати або замінити на однаковий global `provider` |

Додайте `schema_version: 1`. Version 1 не дозволяє mixed deployment. Старий
mixed config потрібно розділити на незалежні AWS/GCP deployments з різними
remote state keys; автоматичної data migration між ними немає.

## 3. Нормалізуйте profiles

- `portable`: рівно одна private VM з role `database`, top-level `database`
  відсутній/null;
- `managed`: database VM відсутня, top-level `database.cloud` збігається з
  `cloud_provider`;
- infra/history/fetcher не мають public IP;
- bastion і UI мають public IP;
- AWS UI internal IP належить `public_subnet_cidr`;
- image SHA і upstream digests immutable.

Перевірте config JSON Schema та `scripts/validate_project_config.py` до
Terraform init.

## 4. Підготуйте foundation

Запустіть `scripts/bootstrap-cloud.sh ... --check`. Перевірте resolved
account/project, region, billing, state bucket і identities. `--yes` потребує
окремого усвідомленого дозволу. Не переносіть один state між providers.

## 5. Узгодьте existing resources

Для кожного існуючого VPC/subnet/address/VM/database/registry/DNS object оберіть
одну дію: import у нову адресу, залишити поза scope або видалити окремою
погодженою операцією. Спочатку зробіть import plan без changes. Existing
Cloudflare record імпортуйте як `module.dns.cloudflare_dns_record.ui`.

Не використовуйте stale local state як джерело істини й не робіть масовий
`terraform state rm` без provider audit.

## 6. Перевірте plan matrix

План конкретного deployment має містити ресурси лише обраного provider,
private database, static UI IP, bastion/UI public access, cloud registry pull
permissions, Cloudflare record і monitoring. PostgreSQL/Redis/RabbitMQ ports не
можуть мати `0.0.0.0/0` ingress.

## 7. Apply та acceptance — окремо

Після окремого дозволу застосуйте saved plan. Потім окремо перевірте повторний
Ansible run, container health, queue flow, persistence, sessions, DNS, TLS,
закриті direct ports, logs, контрольований 5xx alarm і фактично запущені image
digests. Успішний Terraform apply сам по собі не є application acceptance.
