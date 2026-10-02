# CI required checks

`.github/workflows/pr-validation.yml` runs on every pull request targeting
`develop` and `main`, and on pushes to `develop`. It validates code,
configuration, tests and Docker image builds. It never publishes an image.

## Checks to mark as required in branch protection

Set these on **both** `develop` and `main`
(Settings → Branches → branch protection rule → *Require status checks to pass
before merging*). The names below are exactly what GitHub reports:

| Check name               | What it guards                                        |
| ------------------------ | ----------------------------------------------------- |
| `YAML`                   | every versioned YAML file parses and passes yamllint   |
| `Python`                 | ruff lint, ruff format, pytest                         |
| `Go`                     | gofmt, go vet, go test                                 |
| `Frontend`               | npm ci, typecheck, production build                    |
| `Docker Compose`         | all Compose files parse and interpolate               |
| `Docker image (database)`| the database/migration image builds                   |
| `Docker image (fetcher)` | the fetcher image builds                              |
| `Docker image (history)` | the history image builds                              |
| `Docker image (ui)`      | the UI image builds                                   |
| `Terraform`              | terraform fmt and validate                            |
| `Ansible Lint`           | the collection builds and lints at the production profile |
| `Helm`                   | every chart lints, renders, and validates against the pinned Kubernetes version |
| `Synthetics canary`      | the canary handler's own test suite                   |

Also enable *Require branches to be up to date before merging*, otherwise two
PRs that each pass individually can still break `develop` when both land.

## Why `Terraform` reports green on a PR that touches no Terraform

A job guarded by an `if:` at the **job** level would be skipped, and a skipped
job reports no status at all — a required check that never reports leaves every
PR stuck on "Expected — waiting for status to be reported".

So the `Terraform` job always runs. Its first step diffs the PR (or the push
range) against `infrastructure/terraform/`; if nothing there changed, the
remaining steps are skipped by a **step**-level `if:` and the job still
finishes green. The same shape would work for any other expensive job.

## What `Helm` proves, and what it does not

It lints the three charts in this repository and renders all six — those three
plus Traefik, the EBS CSI driver and cert-manager at the versions pinned in
`infrastructure/helm/versions.yml` — then validates the output with
`kubeconform -strict`. That is what catches a values key a chart does not
accept, or an API version removed in the Kubernetes release being targeted,
without needing a cluster.

It renders with **placeholder digests and example hostnames**, because the real
project configuration is not in this repository. So it proves the templates are
valid, not that your values are. Nothing in CI validates the real
configuration — see [k3s-deployment.md](k3s-deployment.md).

Two ways this job can go red without anyone having broken anything:
`kubeconform` fetches CRD schemas from the datree catalog on GitHub, so a
network blip reads as a failure; and the upstream chart repositories must be
reachable for `helm template --repo` to resolve a version.

## Deliberately removed

`terraform test` used to run in the `Terraform` job. There are no
`.tftest.hcl` files in the repository and, by project convention, there will
not be — so the step passed having asserted nothing. A step that cannot fail
is worse than no step, because the check name reads as coverage.

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
* Terraform: `terraform -chdir=infrastructure/terraform fmt -check -recursive`
  then `init -backend=false && validate`. No credentials are needed for either.
* Helm: `helm lint infrastructure/helm/charts/<chart>`. To reproduce the render
  step you need the same `--set` placeholders the workflow passes; read them out
  of the `Render and validate every chart` step rather than inventing values.
* Ansible: `ansible-lint` from `infrastructure/ansible`, with the collections
  from `requirements.yml` installed.

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
