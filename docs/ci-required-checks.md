# CI required checks

`.github/workflows/pr-validation.yml` runs on every pull request targeting
`develop` and `main`, and on pushes to `develop`. It validates code,
configuration, tests and Docker image builds. It never publishes an image.

## Checks to mark as required in branch protection

Set these on **both** `develop` and `main`
(Settings → Branches → branch protection rule → *Require status checks to pass
before merging*). The names below are exactly what GitHub reports:

| Check name              | What it guards                                        |
| ----------------------- | ----------------------------------------------------- |
| `YAML`                  | every versioned YAML file parses and passes yamllint   |
| `Python`                | ruff lint, ruff format, pytest                         |
| `Go`                    | gofmt, go vet, go test                                 |
| `Frontend`              | npm ci, typecheck, production build                    |
| `Docker Compose`        | all Compose files parse and interpolate                |
| `Docker image (fetcher)`| the fetcher image builds                               |
| `Docker image (history)`| the history image builds                               |
| `Docker image (ui)`     | the UI image builds                                    |
| `Terraform`             | terraform fmt and validate, once Terraform exists      |

Also enable *Require branches to be up to date before merging*, otherwise two
PRs that each pass individually can still break `develop` when both land.

## Why `Terraform` is safe to require now

There is no Terraform in the repository yet. A job guarded by an `if:` at the
job level would be **skipped**, and a skipped job reports no status at all — a
required check that never reports leaves every PR stuck on "Expected — waiting
for status to be reported".

So the `Terraform` job always runs. Its first step looks for any `*.tf` file;
if none exists it logs that and the remaining steps are skipped, so the job
still finishes green. The moment someone adds Terraform, `fmt -check` and
`validate` start running against it with no change to branch protection.

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
