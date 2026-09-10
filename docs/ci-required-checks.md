# CI required checks

`.github/workflows/pr-validation.yml` runs on every pull request targeting
`develop` and `main`, and on pushes to `develop`. It validates code,
configuration, tests and Docker image builds. It never publishes an image.

## Checks to mark as required in branch protection

Set these on **both** `develop` and `main`
(Settings → Branches → branch protection rule → *Require status checks to pass
before merging*). The names below are exactly what GitHub reports:

| Check name               | What it guards                                           |
| ------------------------ | -------------------------------------------------------- |
| `YAML`                   | every versioned YAML file parses and passes yamllint      |
| `Python`                 | ruff lint, ruff format, pytest                            |
| `Go`                     | gofmt, go vet, go test                                    |
| `Frontend`               | npm ci, typecheck, production build                       |
| `Docker Compose`         | local and historical combined Compose definitions parse  |
| `Docker image (database)` | the PostgreSQL application image builds                  |
| `Docker image (fetcher)` | the fetcher image builds                                  |
| `Docker image (history)` | the history image builds                                  |
| `Docker image (ui)`      | the UI image builds                                       |
| `Terraform`              | Terraform formatting, validation, and cloud-init schema   |

Also enable *Require branches to be up to date before merging*, otherwise two
PRs that each pass individually can still break `develop` when both land.

## Terraform change detection

The `Terraform` job always reports a status so it can remain a required check.
It compares the pull request or push range for changes under
`infrastructure/terraform/`. When Terraform files are unchanged, the setup and
validation steps are skipped while the job still finishes successfully. When
they change, CI runs `terraform fmt -check`, initializes without the remote
backend, validates the configuration, and validates the active bastion
cloud-init template.

## Notes for people writing PRs

* Python is managed with `uv`. Reproduce CI locally with:
  `uv sync --frozen && uv run ruff check . && uv run ruff format --check . && uv run pytest`
* Go lives in `services/fetcher`:
  `gofmt -l . && go vet ./... && go test ./...`
* Frontend lives in `services/ui/frontend`:
  `npm ci && npm run typecheck && npm run build`
* YAML: `yamllint -c .yamllint.yml .`
* Compose files use `${VAR:?...}` for required settings, so `docker compose
  config` needs those variables defined. The workflow supplies throwaway values;
  locally, export the required values in the parent shell.

## Deliberately not here

Image publishing. This workflow builds images to prove the Dockerfiles are
valid and throws them away (`push: false`). Pushing to a registry belongs in a
separate workflow triggered from `develop`/`main`, not from pull requests —
a PR from a fork must never be able to publish an image.

## Security checks

`.github/workflows/security.yml` adds four more checks: `Secret scan`,
`IaC scan`, `Dependency scan` and `CodeQL (…)`. Only the first two are intended
to be required — see [security-scanning.md](security-scanning.md) for why the
other two report rather than block.
