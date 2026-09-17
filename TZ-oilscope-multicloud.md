# Технічне завдання: конфігураційний multi-cloud deployment OilScope

## 1. Мета

Переробити поточну GCP-орієнтовану інфраструктуру OilScope так, щоб один репозиторій і один логічний формат `project-config` підтримували два стабільні незалежні режими розгортання:

1. увесь deployment у GCP;
2. увесь deployment в AWS.

На цьому етапі не реалізовувати одночасне розміщення різних VM у різних хмарах. Архітектура конфігурації, Terraform-модулів, outputs та Ansible inventory має дозволяти в майбутньому додати provider для кожної VM без повного переписування рішення.

Поточний runtime залишається VM + Docker Compose. Структуру проєкту необхідно підготувати до майбутнього додавання k3s з мінімальними змінами, але не встановлювати й не запускати k3s у межах цього завдання.

## 2. Основні принципи

- Спільна конфігурація описує намір проєкту, а не назви ресурсів AWS або GCP.
- AWS і GCP реалізуються окремими provider-specific Terraform-модулями зі спільним логічним контрактом.
- Не створювати один великий модуль із перемішаними ресурсами AWS і GCP.
- Не дублювати повністю Ansible для кожної хмари. Ansible організувати навколо ролей машин і компонентів.
- Не передавати секрети як відкриті значення в JSON, Terraform variables, outputs, inventory або Git.
- Не використовувати рухомі Docker tags як джерело істини для deployment.
- Не давати PostgreSQL, Redis або RabbitMQ прямого доступу з Інтернету.
- Успішний `terraform apply` не вважати доказом працездатності застосунку. Інфраструктурну, конфігураційну та application acceptance перевірки виконувати окремо.
- Не виконувати live `terraform apply`, створення платних ресурсів, зміну DNS або видалення ресурсів без окремого підтвердження користувача.
- Перед змінами прочитати README, документацію deployment, поточний Terraform, Ansible, CI workflows, тести та приклади конфігурації.
- Зберігати сторонні зміни в робочому дереві. Робити невеликі логічні комміти після завершення і перевірки кожного етапу.

## 3. Межі поточного етапу

### Реалізувати

- глобальний вибір `aws` або `gcp` для всього deployment;
- спільну модель конфігурації;
- idempotent bootstrap script для підготовки cloud foundation перед `terraform init/apply`;
- окремі AWS- і GCP-модулі;
- нормалізовані Terraform outputs;
- режими даних `portable` та `managed`;
- приватну БД;
- bastion із публічною IP та обмеженим SSH-доступом;
- UI зі статичною публічною IP, Cloudflare DNS і HTTPS;
- cloud-specific registry в ECR або Artifact Registry;
- role-based Ansible;
- базовий моніторинг AWS і GCP;
- application/log monitoring для HTTP 5xx;
- документацію, приклади конфігів, валідацію та тести;
- архітектурні межі для майбутнього k3s.

### Не реалізовувати зараз

- одночасний mixed deployment AWS + GCP;
- VPN між AWS і GCP;
- provider selection для окремих VM у live deployment;
- Kubernetes/k3s manifests, Helm charts або встановлення k3s;
- автоматичну міграцію даних між PostgreSQL-режимами;
- managed Redis або managed RabbitMQ, якщо це прямо не підтримується поточним проєктом;
- production HA, autoscaling або multi-region deployment.

## 4. Попередній аудит

Перед реалізацією Codex має:

1. Знайти фактичний entrypoint Terraform та всі root/modules.
2. Визначити, які ресурси вже створюються для GCP.
3. Перевірити фактичну структуру Terraform state/backend.
4. Перевірити Ansible inventory, playbooks, roles, ProxyJump через bastion і спосіб передачі secrets.
5. Перевірити фактичну реалізацію queue та sessions:
   - чи використовується PostgreSQL extension;
   - чи використовується portable SQL queue через `FOR UPDATE SKIP LOCKED`;
   - чи вже існують RabbitMQ та Redis backends.
6. Перевірити Docker Compose-файли та назви environment variables.
7. Перевірити workflows, які збирають і публікують Fetcher, History, UI та custom PostgreSQL.
8. Перевірити, де зараз живе DNS-конфігурація та чи є Cloudflare provider.
9. Перевірити поточне логування HTTP-запитів і можливість надійно виділяти статуси 5xx.
10. Перевірити, чи вже існують bootstrap/foundation scripts, remote-state resources, CI identities або вручну створені IAM bindings, які потрібно зберегти чи імпортувати.
11. Зафіксувати короткий baseline-звіт до початку рефакторингу.

Якщо README не відповідає коду, вважати код поточним станом, а README — цільовою або застарілою документацією. Розбіжності перелічити окремо.

## 5. Нова модель `project-config`

### 5.1. Загальні вимоги

Додати версію схеми, наприклад `schema_version`, та глобальний `cloud_provider` зі значенням `aws` або `gcp`.

Спільний конфіг має містити логічні секції:

- project/deployment metadata;
- provider account/project settings;
- network intent;
- compute profiles;
- VM roles;
- runtime/data profile;
- images/registry;
- secrets references;
- ingress/DNS/TLS;
- observability;
- deployment runtime.

Не копіювати точну запропоновану структуру механічно. Спочатку адаптувати її до поточного коду й забезпечити backward-compatible migration або чітку помилку зі зрозумілою інструкцією.

### 5.2. Provider settings

GCP-specific поля, наприклад `project_id`, мають знаходитися в GCP-секції. AWS-specific поля, наприклад account/profile/region settings, — в AWS-секції.

`region` і `zone` можуть мати спільні логічні назви, але їх значення валідовуються відповідно до вибраного provider.

Не зберігати cloud credentials у JSON. Використовувати стандартні provider credential chains:

- Application Default Credentials або service account/workload identity для GCP;
- AWS profile, environment або IAM role/OIDC для AWS.

### 5.3. Майбутній provider per VM

Передбачити опціональне поле `provider` у визначенні VM або еквівалентний механізм успадкування:

- зараз VM успадковує глобальний `cloud_provider`;
- якщо `provider` вказаний явно, він має дорівнювати глобальному provider;
- mixed значення на цьому етапі відхиляти валідацією з повідомленням, що режим зарезервований для майбутньої реалізації.

Не закладати припущення, що всі VM назавжди знаходитимуться в одній VPC/VNet. Водночас не створювати VPN або mixed networking зараз.

## 6. Словник загальних ресурсів

Створити канонічний словник або typed mapping, який перетворює логічні значення на provider-specific параметри.

Мінімально підтримати:

| Логічне поняття | GCP | AWS |
|---|---|---|
| compute class | GCE machine type | EC2 instance type |
| disk class | Persistent Disk type | EBS volume type |
| OS image | GCP image family/project | AMI lookup |
| architecture | amd64/arm64 | amd64/arm64-compatible AMI та instance |
| access profile | network tags/firewall | security groups |
| static public IP | reserved address | Elastic IP |
| secret reference | Secret Manager | Secrets Manager/Parameter Store згідно з прийнятим рішенням |

У `project-config` використовувати логічні значення на кшталт `micro`, `small`, `balanced`, `ubuntu-lts`, `amd64`, а не `e2-micro`, `t3.micro`, `pd-balanced` або `gp3`.

Дозволити обмежений provider override лише там, де він справді потрібний. Override не повинен бути основним способом конфігурації.

AMI не хардкодити глобально: образ AWS має коректно визначатися для вибраного регіону та архітектури. Усі результати lookup мають бути передбачуваними та перевіреними.

## 7. Terraform-модулі

### 7.1. Організація

Організувати окремі реалізації щонайменше для:

- network;
- compute/VM;
- managed PostgreSQL;
- registry;
- secrets integration;
- ingress/public IP/DNS;
- monitoring.

AWS і GCP modules можуть мати різну внутрішню структуру, але root orchestration має подавати їм нормалізовані inputs і отримувати нормалізовані outputs.

Terraform не повинен намагатися динамічно змінювати тип ресурсу або backend. Root orchestration має явно створювати тільки модулі вибраного provider на основі plan-known значення.

### 7.2. Нормалізовані outputs

Обидві реалізації мають повертати однаковий логічний контракт, зокрема:

- deployment/provider/environment;
- VM logical name і role;
- private IP або private hostname;
- public IP, якщо вона існує;
- bastion endpoint;
- UI endpoint;
- SSH user/port і ProxyJump metadata без private keys;
- database endpoint без пароля;
- registry image URIs;
- DNS hostname;
- monitoring identifiers.

Outputs не повинні містити secret values.

### 7.3. State

Передбачити окремий state namespace/backend key для:

- environment;
- provider;
- deployment name.

Не покладатися на Terraform variables для динамічного вибору backend, оскільки backend ініціалізується раніше. Використати окремі backend config files, wrapper command/script або інший прозорий підхід, сумісний із поточним репозиторієм.

Не переносити і не імпортувати live state без окремого плану та підтвердження.

### 7.4. Bootstrap cloud foundation

Написати єдиний керований entrypoint, наприклад `scripts/bootstrap-cloud.sh`, із provider-specific внутрішніми функціями або підкомандами для `gcp` та `aws`.

Bootstrap запускається до основного `terraform init/plan/apply` і готує лише foundation-ресурси, без яких основний Terraform не може безпечно стартувати.

#### Загальні вимоги

- Підтримати явні аргументи щонайменше для provider, environment, deployment name, region та шляху до project config.
- Мати режим `--check` або `--dry-run`, який нічого не змінює і показує, що існує, чого бракує та які дії будуть виконані.
- Для state-changing запуску вимагати явне підтвердження або прапорець `--yes`.
- Бути idempotent: повторний запуск не створює дублікати, не змінює credentials без потреби й не скидає IAM policy.
- Перед змінами виводити активний GCP account/project або AWS identity/account/region і вимагати підтвердження правильного target.
- Перевіряти наявність і версії потрібних CLI: `gcloud`, `aws`, `terraform`, `jq` та інших фактично використаних утиліт.
- Завершуватися при першій помилці, мати зрозумілі повідомлення та не приховувати частково виконаний стан.
- Не виконувати destructive cleanup. Видалення foundation має бути окремим, явно підтвердженим процесом поза bootstrap.
- Не створювати workload network, VM, RDS/Cloud SQL, application secrets, DNS records, monitoring dashboards або application registries, якщо вони належать основному Terraform.
- Чітко розділити ресурси, якими володіє bootstrap, і ресурси, якими володіє основний Terraform, щоб один інструмент не перезаписував state іншого.

#### GCP bootstrap

Для GCP bootstrap має вміти:

1. Перевірити активного користувача/identity та його права.
2. Знайти існуючий project або, якщо конфігурація явно дозволяє, створити новий GCP project у вказаній organization/folder.
3. Прив'язати billing account до нового project лише після явного підтвердження.
4. Не відключати billing і не змінювати organization/folder існуючого project автоматично.
5. Увімкнути тільки API, необхідні фактичній реалізації, зокрема API для:
   - Resource Manager/Service Usage;
   - IAM та IAM Credentials;
   - Compute Engine;
   - Secret Manager;
   - Artifact Registry;
   - Cloud Logging і Cloud Monitoring;
   - Cloud SQL Admin та Service Networking для `managed` profile;
   - інших сервісів лише після підтвердження їх використання кодом.
6. Створити окремі service accounts або еквівалентні identities щонайменше для:
   - Terraform deployment;
   - CI image publishing/promotion;
   - VM runtime/pull access;
   - monitoring/logging, якщо окрема identity справді потрібна.
7. Видати least-privilege roles відповідно до обов'язків. Не використовувати `roles/owner` або `roles/editor` як постійне рішення.
8. Підготувати GCS bucket для remote Terraform state:
   - globally unique name;
   - versioning;
   - uniform bucket-level access;
   - public access prevention;
   - encryption згідно з прийнятою політикою;
   - окремий state prefix для environment/provider/deployment.
9. Надати Terraform deployment identity необхідний доступ до state bucket та ресурсів, які створює основний Terraform.
10. За можливості використовувати impersonation/workload identity federation замість service-account key files.

Якщо створення project неможливе через відсутність organization, folder, billing account або прав, bootstrap має зупинитися з конкретним списком відсутніх prerequisites, а не продовжувати в частково готовому стані.

#### AWS bootstrap

AWS не має прямого аналога створення GCP project усередині звичайного account. Тому bootstrap має:

1. Перевірити активну AWS identity через STS, account ID та вибраний region.
2. Працювати в існуючому AWS account; створення нового AWS Organization account не входить у scope, якщо це не буде окремо погоджено.
3. Підготувати project namespace через узгоджені names/tags/prefixes.
4. Створити або перевірити IAM roles/instance profiles щонайменше для:
   - Terraform deployment;
   - CI image publishing/promotion;
   - EC2 runtime і ECR pull;
   - CloudWatch/SSM integration, якщо вони використовуються.
5. Для GitHub Actions віддавати перевагу OIDC trust та короткоживучим credentials замість IAM access keys.
6. Підготувати S3 bucket для remote Terraform state:
   - globally unique name;
   - versioning;
   - block public access;
   - encryption;
   - окремий state key/prefix для environment/provider/deployment;
   - state locking, сумісний із зафіксованою у проєкті версією Terraform і обраним S3 backend.
7. Надати deployment role мінімально необхідний доступ до state і ресурсів основного Terraform.
8. Перевірити доступність потрібних AWS services/quotas у region та створити service-linked roles лише якщо вони реально потрібні.

Не створювати IAM users із довгоживучими access keys за замовчуванням. Для людей використовувати існуючі federated/SSO principals і призначати їм погоджені ролі. Якщо legacy IAM user справді необхідний, це має бути окремий opt-in режим без автоматичного створення або виведення access key у лог.

#### Користувачі та runtime identities

Чітко розділити три типи identities:

- cloud operator/developer principals — існуючі люди через SSO/federation або явні principal IDs;
- automation identities — Terraform і CI;
- runtime identities — GCE/EC2 workloads із мінімальними правами на registry, secrets і monitoring.

Linux `ssh_users` на VM не створювати foundation bootstrap-скриптом. Їх створення та SSH authorized keys залишаються відповідальністю VM bootstrap/Ansible, щоб cloud IAM і OS users не змішувалися.

Не давати всім identities однакову широку роль. Окремо визначити:

- хто може змінювати infrastructure;
- хто може читати/писати Terraform state;
- хто може публікувати images;
- хто може лише завантажувати images;
- хто може читати конкретні secrets;
- хто може писати logs/metrics.

#### Bootstrap outputs

Після успішного запуску створити локальний machine-readable foundation manifest та backend config у gitignored директорії, наприклад `.generated/<environment>/<provider>/`, без секретів.

Manifest може містити:

- provider;
- account/project ID;
- region;
- deployment identity email/ARN;
- runtime identity email/ARN;
- state bucket;
- state prefix/key;
- OIDC/CI role identifiers;
- enabled services/API;
- timestamp і schema version.

Bootstrap має вивести точні наступні команди для:

1. credential/role activation або impersonation;
2. `terraform init` із правильним backend config;
3. config validation;
4. `terraform plan`.

Не запускати `terraform apply` автоматично з bootstrap.

#### Bootstrap secrets і безпека

- Не друкувати tokens, access keys, private keys або secret values.
- Не зберігати service-account JSON keys, AWS access keys або Cloudflare token у generated files.
- Усі generated files із локальними identifiers/backend settings додати до `.gitignore`, крім безпечного template/example.
- Перед записом файлу перевіряти permissions; sensitive local artifacts, якщо вони взагалі потрібні, створювати з режимом `0600`.
- Не змінювати існуючі IAM bindings шляхом повної заміни policy, якщо можна додати точковий binding/member.
- Виводити попередження про IAM propagation delay та повторно перевіряти доступ перед завершенням.

#### Bootstrap acceptance criteria

- `--check` не змінює cloud state.
- Перший підтверджений запуск створює лише задокументовані foundation resources.
- Другий запуск не створює дублікатів і не показує неочікуваних змін.
- Неправильний account/project/region зупиняє процес до мутації.
- Після bootstrap виконується `terraform init` із remote backend.
- Deployment identity може виконати `terraform plan`.
- Deployment identity не має постійної Owner/Administrator ролі без обґрунтування.
- Runtime identity не може змінювати infrastructure або Terraform state.
- CI identity може публікувати images, але не отримує непотрібний адміністративний доступ.
- Жоден credential або secret не потрапляє в Git, stdout/stderr чи foundation manifest.
- Shell script проходить `shellcheck`; критична логіка покрита Bats або еквівалентними тестами з mocked CLI responses.
- Документація містить prerequisites, приклади команд, очікувані ресурси, permission model і troubleshooting.

## 8. Networking і доступ

### 8.1. CIDR

Змінити приклади мережі так, щоб вони були сумісні щонайменше з AWS та GCP:

- management subnet не менше `/28`;
- workload subnet може залишатися `/26` або бути ширшою;
- не використовувати для VM адреси, зарезервовані AWS;
- рекомендувати VM addresses із безпечного діапазону, наприклад починаючи з `.10`;
- додати валідацію CIDR та internal IP.

Для майбутнього mixed deployment документувати вимогу непересічних AWS і GCP CIDR, але не реалізовувати міжхмарні маршрути зараз.

### 8.2. Bastion

- Bastion має публічну IP.
- Публічна IP має бути статичною, якщо вона використовується в стабільному inventory/allowlist.
- SSH доступ дозволяти лише з `allowed_cidrs`.
- Зберегти configurable SSH port, включно з поточним нестандартним портом, якщо він реально використовується.
- Workload VM не повинні мати публічні SSH endpoints.
- Ansible має підключатися до workload VM через bastion/ProxyJump.
- Private SSH keys не створювати у Terraform state і не коммітити.

### 8.3. Workload firewall

- UI: публічно лише 80/443; application port не відкривати напряму назовні.
- History API: доступ лише від UI та необхідних internal clients.
- Fetcher diagnostics: лише приватна мережа або monitoring sources.
- PostgreSQL: лише від тих ролей, яким він фактично потрібен.
- Redis і RabbitMQ: лише від application roles, яким вони потрібні.
- Administrative доступ до internal services — через bastion або керований cloud mechanism.

Firewall/security group rules будувати за логічними access profiles, а не за GCP `network_tags` у спільній конфігурації.

## 9. Data profile

Додати явний параметр `data_profile` або `runtime_profile` зі значеннями `portable` і `managed`.

### 9.1. `portable`

- Custom PostgreSQL запускається в контейнері на приватній infra/database VM.
- PostgreSQL не має public IP і не доступний з Інтернету.
- Queue backend — PostgreSQL portable queue.
- Session backend — PostgreSQL.
- Зберігання даних використовує persistent volume/disk.
- Повторний deployment не повинен видаляти дані без явної destructive операції.
- Перевірити міграції, queue visibility/retry/archive та idempotency.

### 9.2. `managed`

- AWS створює RDS PostgreSQL.
- GCP створює Cloud SQL for PostgreSQL.
- Managed PostgreSQL має лише private endpoint/private IP.
- Public database access заборонений.
- Queue backend — RabbitMQ.
- Session backend — Redis.
- RabbitMQ і Redis працюють як контейнерні сервіси на приватній infra VM, якщо аудит поточного проєкту не покаже обґрунтовану іншу топологію.
- RDS/Cloud SQL credentials зберігаються в cloud secrets manager.
- Security groups/firewall дозволяють DB connection тільки фактичним клієнтам і migration runner.
- Не припускати наявність `pgmq` або іншого extension, поки його підтримка не підтверджена для конкретного managed PostgreSQL.

### 9.3. Application environment contract

Compose/Ansible мають формувати однаковий application contract незалежно від provider:

- `DATABASE_URL`;
- `QUEUE_BACKEND`;
- RabbitMQ connection settings лише для `managed`;
- `SESSION_BACKEND`;
- Redis connection settings лише для `managed`;
- service discovery endpoints;
- secure cookie setting для HTTPS.

Застосунки не повинні визначати cloud provider і не повинні мати AWS/GCP-specific branching.

## 10. Container registries та tags

### 10.1. Власні образи

Підтримати:

- Fetcher;
- History;
- UI;
- custom PostgreSQL.

Поточні GHCR images використати як source artifacts. Не перебудовувати різний образ для AWS і GCP. Один і той самий digest має копіюватися:

- в Amazon ECR для AWS deployment;
- в Artifact Registry для GCP deployment.

Terraform створює registry repositories та IAM permissions, але не повинен виконувати `docker push` через `local-exec`.

Копіювання/публікацію реалізувати в CI workflow або окремому явному script/command.

### 10.2. Сторонні образи

Дзеркалити в cloud registry зафіксовані upstream versions/digests:

- Redis;
- RabbitMQ.

Не використовувати непінований `latest`.

### 10.3. Tag policy

Обов'язковий immutable tag:

- повний commit SHA або `sha-<full-sha>` для власних образів;
- точна upstream version плюс перевірений digest для Redis/RabbitMQ.

Додаткові зрозумілі tags дозволені:

- `main`;
- `develop`;
- `vX.Y.Z`;
- `release-X.Y`;
- `main-<short-sha>`.

Deployment має використовувати immutable SHA tag або digest. Moving tags існують лише для зручності людини.

Додати OCI labels щонайменше з source repository, revision, version і build time.

Після копіювання перевіряти, що digest source image та cloud registry image збігається.

VM не повинні потребувати довгоживучого GHCR token після переходу на cloud registry. Для ECR/GAR використовувати IAM role/service account із мінімальними pull permissions.

## 11. Ansible

### 11.1. Role-based організація

Ansible організувати навколо capabilities/roles, а не хмар:

- common OS baseline;
- Docker Engine;
- Compose runtime;
- application deployment;
- bastion;
- infra/data services;
- fetcher;
- history;
- UI;
- reverse proxy/TLS;
- monitoring agent.

Provider-specific tasks дозволені лише для реальних відмінностей:

- package repository/bootstrap;
- cloud monitoring agent;
- cloud identity/registry authentication;
- metadata integration.

Не створювати дві повні копії playbooks для AWS і GCP.

### 11.2. Inventory

- Генерувати inventory з нормалізованих Terraform outputs.
- Групувати hosts за логічною роллю.
- Зберегти ProxyJump через bastion.
- Не хардкодити GCP inventory names або IP у playbooks.
- Не записувати secrets у згенерований inventory.

### 11.3. Idempotency

Повторний запуск Ansible без змін конфігурації не повинен перезапускати або перевстановлювати все без необхідності.

Compose deployment має використовувати pinned image references і виконувати health checks.

## 12. Domain, Cloudflare і HTTPS

Домен зареєстрований у NIC.UA, але authoritative nameservers знаходяться в Cloudflare. Отже DNS-записами керувати через Cloudflare API/provider, а не через NIC.UA.

На поточному етапі реалізувати спільний для двох хмар простий ingress:

1. UI VM отримує статичну public IP:
   - reserved external address у GCP;
   - Elastic IP в AWS.
2. Terraform створює/оновлює Cloudflare `A` record для заданого hostname.
3. На першому стабільному етапі record може бути `proxied=false`, щоб origin TLS і діагностика не залежали від Cloudflare proxy. Зробити `proxied` конфігурованим.
4. Ansible встановлює Caddy або зберігає поточний reverse proxy, якщо він уже коректно реалізований.
5. Reverse proxy автоматично отримує публічний ACME certificate для hostname.
6. Reverse proxy слухає 80/443 і проксіює UI на внутрішній application port.
7. У production HTTPS увімкнути secure cookie.

Cloudflare API token передавати через environment/secret store. Не коммітити й не записувати його у відкритий config.

Terraform dependency має гарантувати, що DNS record використовує створену статичну IP. Provisioning workflow має дочекатися DNS resolution, запуску reverse proxy та валідного HTTPS, але враховувати, що DNS/ACME можуть потребувати часу.

Не заявляти про готовність HTTPS лише на підставі створеного DNS record. Виконати зовнішню перевірку:

- hostname резолвиться у правильну IP;
- TLS certificate валідний для hostname;
- `https://<hostname>/` відповідає;
- `https://<hostname>/health` або погоджений health endpoint відповідає;
- прямий application port не відкритий з Інтернету.

Cloud load balancer + ACM/GCP managed certificate залишити як документований майбутній варіант, а не реалізовувати разом із Caddy в межах цього етапу.

## 13. Monitoring та логування

### 13.1. Спільний monitoring contract

Для AWS і GCP забезпечити логічно однакові сигнали:

- VM CPU;
- memory utilization;
- disk utilization;
- VM/agent availability;
- container restarts або unhealthy state;
- application health;
- HTTP request count;
- HTTP latency, якщо доступна;
- HTTP 5xx count;
- PostgreSQL availability;
- queue/RabbitMQ availability та backlog, якщо доступний;
- Redis availability;
- зовнішня HTTPS availability.

### 13.2. Provider implementations

AWS:

- CloudWatch Agent;
- CloudWatch Logs;
- metric filters/alarms для 5xx;
- dashboard;
- HTTPS availability check через придатний AWS mechanism.

GCP:

- Ops Agent;
- Cloud Logging;
- log-based metrics/alerting для 5xx;
- Cloud Monitoring dashboard;
- uptime check для HTTPS endpoint.

### 13.3. HTTP 5xx

Спочатку перевірити формат application logs. Якщо він неструктурований, додати структуроване JSON logging або стабільний access-log format із полями:

- timestamp;
- service;
- method;
- route/path;
- status;
- duration;
- request/correlation ID без персональних або секретних даних.

5xx metric будувати за полем status, а не за випадковим входженням тексту `500`.

Додати alarm threshold/window як конфігуровані значення. Notification channels не хардкодити; зробити їх опціональними inputs.

### 13.4. Log safety

Не логувати:

- API keys;
- database passwords;
- cookies/session identifiers;
- registry tokens;
- Authorization headers;
- повні secret payloads.

## 14. Підготовка до k3s

k3s не встановлювати в межах цього завдання. Необхідно підготувати межі, щоб майбутній перехід вимагав додавання нового runtime adapter, а не переписування cloud infrastructure та застосунків.

### 14.1. Runtime abstraction

Передбачити логічний параметр deployment runtime, де зараз підтримується тільки `compose`, а `k3s` зарезервований і відхиляється зрозумілою валідацією до появи реалізації.

Не розміщувати Compose-specific поля у верхньому спільному application contract. Compose files, systemd units і Docker installation мають знаходитися в окремому runtime layer.

### 14.2. Вимоги до застосунків

- Усі application images мають бути OCI-сумісними й запускатися без cloud-specific логіки.
- Конфігурація застосунків — через environment variables/secrets.
- Health endpoints мають підходити для майбутніх readiness/liveness probes.
- Процеси повинні коректно обробляти SIGTERM і мати передбачуваний startup/shutdown.
- Не використовувати hardcoded VM IP у коді застосунку.
- Service endpoints мають передаватися через конфігурацію, щоб пізніше замінити їх на Kubernetes Service DNS.
- Дані та тимчасові файли чітко розділити; stateless application containers не повинні залежати від локального диска VM.

### 14.3. Terraform і node contract

Cloud network/compute modules не повинні знати деталі Docker Compose services. Вони мають повертати загальний node contract:

- node role;
- addresses;
- architecture;
- labels/tags;
- disk attachments;
- identity;
- registry access;
- security profiles.

У майбутньому той самий compute layer має дозволити створити k3s server/agent nodes або бути заміненим managed Kubernetes module без зміни registry, DNS і application image pipeline.

### 14.4. Ansible boundaries

Розділити:

- OS/node preparation;
- container runtime/common packages;
- Compose deployment;
- monitoring;
- application configuration.

Майбутній k3s role повинен мати змогу повторно використати OS baseline, registry access, secrets bootstrap та monitoring, замінивши лише Compose runtime/deployment layer.

### 14.5. Ingress, secrets і observability

У спільному конфігу зберігати логічні поняття `hostname`, `tls`, `secret reference`, `service`, `health check`, а не Caddy-only або Compose-only структури.

У майбутньому:

- Caddy VM ingress може бути замінений k3s Ingress Controller;
- cloud secrets integration — External Secrets/CSI або іншим adapter;
- monitoring agents — DaemonSet/collectors;
- application settings — ConfigMap/Secret generation.

Поточна реалізація не повинна заважати такій заміні.

### 14.6. Stateful компоненти

Документувати, що managed data profile є простішим шляхом до k3s, оскільки RDS/Cloud SQL живуть поза кластером.

Для майбутнього portable profile в k3s окремо знадобляться:

- StorageClass/PersistentVolumeClaim;
- backup/restore;
- scheduling constraints;
- upgrade strategy;
- рішення щодо PostgreSQL operator або StatefulSet.

Це не реалізовувати зараз і не маскувати як просту конвертацію Compose у Kubernetes YAML.

## 15. Валідація конфігурації

Додати ранню перевірку до Terraform plan:

- підтримуваний `schema_version`;
- `cloud_provider` тільки `aws` або `gcp`;
- `data_profile` тільки `portable` або `managed`;
- runtime тільки `compose` на цьому етапі;
- усі VM використовують глобальний provider;
- CIDR допустимі для обраного provider;
- internal IP належить subnet і не є зарезервованою;
- subnet CIDR не перетинаються;
- `assign_public_ip=false` для infra/history/fetcher;
- database public access вимкнений;
- hostname та required ingress fields задані;
- image reference pinned;
- secret mapping містить reference/name, а не очевидне secret value;
- необхідні provider-specific settings присутні;
- несумісні параметри дають зрозуміле повідомлення.

## 16. Тести та acceptance criteria

### 16.1. Static tests

- Terraform formatting проходить.
- `terraform validate` проходить для AWS і GCP root configurations.
- Terraform tests або еквівалентні unit/static checks покривають обидва providers і обидва data profiles.
- Ansible syntax check проходить.
- Ansible lint проходить у погодженому scope.
- JSON schema/config validation має позитивні й негативні тести.
- Bootstrap `--check`, idempotency та error paths покриті тестами з mocked cloud CLI; `shellcheck` проходить.
- Docker Compose config validation проходить для `portable` і `managed`.
- Application unit/integration tests залишаються зеленими.
- Secret scan не знаходить credentials.

### 16.2. Required plans

Без live apply підготувати й перевірити плани для матриці:

| Provider | Data profile |
|---|---|
| GCP | portable |
| GCP | managed |
| AWS | portable |
| AWS | managed |

У кожному plan перевірити:

- створюються ресурси лише вибраного provider;
- БД не має public endpoint;
- тільки bastion і UI мають передбачені public IP;
- UI IP статична;
- firewall не відкриває PostgreSQL/Redis/RabbitMQ у `0.0.0.0/0`;
- registry repositories та pull permissions коректні;
- DNS record посилається на UI static IP;
- monitoring resources створюються для вибраного provider;
- outputs відповідають спільному контракту.

### 16.3. Live acceptance після окремого дозволу

Для кожної дозволеної конфігурації перевірити окремо:

1. Terraform apply завершився.
2. Ansible завершився й повторний запуск є idempotent.
3. Усі потрібні containers healthy.
4. Workload VM не мають public IP.
5. DB недоступна з Інтернету.
6. DB доступна лише потрібним internal clients.
7. Fetcher публікує тестову подію.
8. History споживає її та зберігає observation.
9. UI читає збережені дані.
10. Session backend відповідає вибраному profile.
11. Hostname резолвиться правильно.
12. HTTPS certificate валідний.
13. Сайт і health endpoint доступні через 443.
14. Пряма зовнішня спроба доступу до application/DB/message-broker ports не проходить.
15. Логи надходять у CloudWatch або Cloud Logging.
16. Контрольований тестовий 5xx створює metric/event без витоку секретів.
17. Dashboard показує основні метрики.
18. Перевірено image digest, який реально запущено.

Infrastructure success, configuration success і application acceptance звітувати окремими секціями.

## 17. Документація

Оновити або створити:

- опис схеми `project-config`;
- приклад AWS config без секретів;
- приклад GCP config без секретів;
- portable/managed profiles;
- mapping логічних compute/disk/image classes;
- registry promotion/mirroring guide;
- Cloudflare token prerequisites і DNS flow;
- Ansible inventory/deployment guide;
- monitoring guide;
- validation/test commands;
- state/backend initialization guide;
- migration guide зі старого GCP config;
- troubleshooting;
- limitations і roadmap для per-VM provider та k3s.

README не повинен заявляти, що режим підтримується, поки для нього не виконані відповідні перевірки. Чітко позначати `implemented`, `statically validated`, `live validated`.

## 18. Рекомендовані етапи та комміти

1. `docs: audit current cloud deployment and define contracts`
2. `feat: add idempotent aws and gcp foundation bootstrap`
3. `refactor: introduce versioned provider-neutral project config`
4. `refactor: extract stable gcp modules without behavior changes`
5. `feat: add aws modules with normalized outputs`
6. `feat: add portable and managed data profiles`
7. `feat: provision ecr and artifact registry image flow`
8. `refactor: generate role-based ansible inventory and roles`
9. `feat: add cloudflare dns and https provisioning`
10. `feat: add aws and gcp monitoring contracts`
11. `test: add provider profile validation matrix`
12. `docs: document deployment bootstrap migration and k3s extension path`

Назви коммітів можна адаптувати до стилю репозиторію. Не робити комміт, якщо відповідний етап не пройшов свої локальні перевірки.

## 19. Формат звіту Codex

Після кожного етапу коротко повідомляти:

- що змінено;
- які файли змінено;
- які перевірки виконано та їх результат;
- що ще не перевірено;
- чи були зроблені припущення;
- hash комміту.

У фінальному звіті окремо надати:

- реалізовані можливості;
- відкладені можливості;
- результати test matrix;
- результати live validation, якщо вона була дозволена;
- security caveats;
- cost-impacting resources;
- manual prerequisites;
- наступний безпечний крок.
