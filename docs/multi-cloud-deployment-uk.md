# Розгортання OilScope в AWS або GCP

## Статус реалізації

Поточний контракт підтримує один provider на deployment, runtime `compose` і
чотири конфігурації:

| Provider | Data profile | Config | Локальна перевірка |
| --- | --- | --- | --- |
| AWS | `portable` | `configs/project-config.aws-portable.json` | mocked Terraform plan пройшов |
| AWS | `managed` | `configs/project-config.aws.json` | mocked Terraform plan пройшов |
| GCP | `portable` | `configs/project-config.gcp-portable.json` | mocked Terraform plan пройшов |
| GCP | `managed` | `configs/project-config.gcp.json` | mocked Terraform plan пройшов |

Це `implemented` і перевірено локальними static/unit tests. Реальні provider
plans, live apply, DNS/HTTPS та application acceptance ще не виконувалися.
`mixed` з AWS+GCP, VPN між хмарами і provider per VM не належать до цього
етапу. `deploy-cloud.sh` навмисно відхиляє legacy config без
`schema_version=1`, щоб не зробити частковий apply за старим контрактом.

## Контракт конфігурації

Обов'язкові глобальні селектори:

```json
{
  "schema_version": 1,
  "cloud_provider": "aws",
  "data_profile": "portable",
  "deployment_runtime": "compose"
}
```

- `cloud_provider`: тільки `aws` або `gcp`;
- `data_profile`: `portable` або `managed`;
- `deployment_runtime`: зараз тільки `compose`;
- усі VM у version 1 мусять використовувати глобальний provider;
- config зберігає лише secret identifiers, а не secret values;
- `registry.image_sha` — повний Git SHA;
- Redis/RabbitMQ source image містить точний `@sha256:` digest.

JSON Schema: `infrastructure/terraform/project-config.schema.json`.
Cross-field правила перевіряє `scripts/validate_project_config.py`: CIDR,
overlap, provider-reserved IP, subnet membership, public IP roles, private DB,
profile roles та immutable image references.

### Логічні provider mappings

| Логічне значення | AWS | GCP |
| --- | --- | --- |
| compute `micro`/`small` | `t3.micro`/`t3.small` | `e2-micro`/`e2-small` |
| disk `balanced` | `gp3` | `pd-balanced` |
| image `ubuntu-lts` | Canonical AMI lookup за region/architecture | Ubuntu image family |
| static UI address | Elastic IP | reserved external address |
| managed PostgreSQL | private RDS | private-IP Cloud SQL |
| registry | private ECR repositories | private Artifact Registry |

Provider escape hatches залишаються в `clouds.aws` і `clouds.gcp`, але
applications не отримують назву provider і не розгалужують business logic.

## Data profiles

`portable` створює приватну VM з role `database`. Custom PostgreSQL забезпечує
дані, SQL queue і UI sessions. RabbitMQ та Redis не запускаються.

`managed` створює private RDS або private-IP Cloud SQL. RabbitMQ і Redis
залишаються контейнерами на History VM: RabbitMQ є queue backend, Redis —
session backend. Managed Redis/RabbitMQ навмисно не додаються на цьому етапі.

В обох режимах PostgreSQL, Redis і RabbitMQ не мають Internet ingress.
Public IP дозволені лише bastion і UI. AWS UI належить public subnet; у GCP UI
отримує reserved address на workload subnet.

## Foundation і remote state

Спочатку виконується read-only перевірка:

```bash
scripts/bootstrap-cloud.sh \
  --provider aws \
  --environment dev \
  --deployment oilscope \
  --region eu-west-1 \
  --config configs/project-config.aws.json \
  --check
```

Для GCP змініть provider, region та config. `--check` не створює cloud або
local state. Лише після перевірки account/project, billing і IAM окремо
дозволяється повторити з `--yes`. Результат записується з mode `0600` у:

```text
.generated/<environment>/<provider>/<deployment>/
├── backend.hcl
└── foundation.json
```

AWS stack використовує S3 backend з native lockfile, GCP — GCS backend.
State key: `<environment>/<provider>/<deployment>/terraform.tfstate`. Деталі й
IAM prerequisites: [foundation-bootstrap.md](foundation-bootstrap.md).

## Registry promotion

Terraform створює immutable targets для Fetcher, History, UI і custom
PostgreSQL. Для managed profile також створюються targets для pinned Redis і
RabbitMQ. VM читають ECR/GAR через IAM role/service account; `GHCR_TOKEN` їм не
передається.

GHCR залишається source artifact. Після Terraform apply явний script копіює
той самий manifest без rebuild:

```bash
terraform -chdir=infrastructure/terraform/stacks/aws output -json registry \
  > /tmp/oilscope-registry.json
scripts/promote-cloud-images.sh \
  configs/project-config.aws.json \
  /tmp/oilscope-registry.json
```

Script порівнює source/target digest, є idempotent для однакового digest і
відмовляється перезаписувати immutable tag іншим manifest. Source SHA має вже
існувати в GHCR. Для private GHCR source deployment environment має містити
`GHCR_TOKEN`; token використовується лише promotion script і не передається на
VM. Promotion не виконується Terraform `local-exec`.

## Cloudflare і HTTPS

Для schema version 1 Cloudflare A-record є Terraform resource і прямо залежить
від static UI IP. Потрібні:

```bash
export CLOUDFLARE_API_TOKEN='...'
export CLOUDFLARE_ZONE_ID='32-character-zone-id'
```

Token повинен мати лише Zone Read та DNS Write для потрібної zone. Zone ID не
є secret, але передається окремо від project config. `proxied` і `ttl` можна
задати в `vms.ui.public_endpoint`; defaults — `false` і `60`.

Якщо A-record вже існує, його потрібно імпортувати у правильний isolated
state до apply, а не створювати дубль. `deploy-cloud.sh` після provisioning
перевіряє public DNS і trusted HTTPS. Traefik зберігається як поточний
коректний reverse proxy, слухає 80/443 і отримує ACME certificate.

## Ansible і outputs

AWS та GCP roots повертають однаковий output `deployment`: nodes, bastion,
database, registry, DNS і monitoring. `scripts/render_ansible_inventory.py`
створює JSON inventory; private nodes отримують ProxyJump через bastion.

Role boundaries:

- `host_baseline`, `docker_engine` — host prerequisites;
- `database`, `history`, `fetcher`, `ui` — workload-specific deployment;
- `cloud_registry_auth` — short-lived ECR/GAR credentials;
- `resolve_secrets` — provider secret backend;
- `edge_proxy` — HTTPS ingress;
- `cloudwatch_agent`/`google_ops_agent` — logs і host metrics.

`deployment_runtime` є явною межею для майбутнього k3s. Terraform node
contract не містить Compose paths, а application images/config/secrets не
залежать від orchestrator. k3s, Helm та manifests зараз не реалізовані.

## Monitoring і безпека логів

UI, History і Fetcher пишуть JSONL у `/var/log/oilscope` з полями:

```text
timestamp, service, event, method, route, status,
duration_ms, request_id
```

Query string, cookies, Authorization і secret payload не записуються. AWS
CloudWatch і GCP Ops Agent читають ці JSONL-файли. HTTP 5xx metric фільтрує
числове поле `status` у подіях `event=http_access`; threshold і window задають
`observability.http_5xx_threshold` та
`observability.http_5xx_window_seconds`.

Також реалізовані CPU, memory, disk, VM availability, DB metrics, dashboard та
зовнішня HTTPS availability. Email subscription/channel потребує live
підтвердження. Monitoring code без контрольованого live 5xx не є доказом
доставки alarm.

## Безпечний deployment flow

Перед будь-яким apply:

1. Перевірити AWS account/GCP project, region, billing і active principal.
2. Перевірити config schema та cross-field contracts.
3. Запустити bootstrap `--check`; окремо погодити `--yes`, якщо foundation
   відсутній.
4. Виконати `terraform init` з generated backend і зберегти plan.
5. Перевірити plan: тільки один provider, private DB, public IP лише bastion/UI,
   закриті data ports, immutable registries, DNS dependency і monitoring.
6. Лише після окремого дозволу застосувати saved plan.
7. Окремо звітувати infrastructure, Ansible configuration та end-to-end
   application acceptance.

`scripts/deploy-cloud.sh` є live workflow і виконує apply; не запускайте його
для read-only перевірки.

## Локальна валідація

```bash
for config in \
  configs/project-config.aws.json \
  configs/project-config.aws-portable.json \
  configs/project-config.gcp.json \
  configs/project-config.gcp-portable.json; do
  uvx check-jsonschema \
    --schemafile infrastructure/terraform/project-config.schema.json \
    "$config"
  python3 scripts/validate_project_config.py "$config"
done

terraform -chdir=infrastructure/terraform fmt -check -recursive
terraform -chdir=infrastructure/terraform validate
terraform -chdir=infrastructure/terraform test
terraform -chdir=infrastructure/terraform/stacks/aws validate
terraform -chdir=infrastructure/terraform/stacks/aws test
terraform -chdir=infrastructure/terraform/stacks/gcp validate
terraform -chdir=infrastructure/terraform/stacks/gcp test
uv run pytest -q
(cd services/fetcher && go test ./...)
```

Mocked Terraform tests не замінюють real provider plan. Ansible syntax/lint,
Compose rendering, shellcheck і secret scanning також залишаються required CI
checks.

## Міграція і troubleshooting

Покрокова міграція зі старого `default_cloud/manage_db/cloud` contract:
[multicloud-migration.md](multicloud-migration.md).

Типові причини ранньої відмови:

- немає `.generated/.../backend.hcl` — bootstrap ще не завершений;
- provider/region не збігається з config — виправте target, не обходьте guard;
- UI IP не в AWS public subnet — використайте адресу з
  `public_subnet_cidr`;
- immutable target має інший digest — створіть новий immutable tag/SHA;
- existing Cloudflare record не в state — імпортуйте його;
- GCP billing не підтверджено — bootstrap не повинен мутувати project;
- image SHA ще не опублікований у GHCR — дочекайтесь publish workflow.

Платними можуть бути VM, public IPv4, RDS/Cloud SQL, logs, synthetic checks,
registries та network egress. Локальні tests не створюють ці ресурси і не
підтверджують нульову вартість.
