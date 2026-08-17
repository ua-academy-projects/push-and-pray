# CI required checks

`.github/workflows/pr-validation.yml` runs on every pull request targeting
`develop` and `main`, and on pushes to `develop`. It validates code,
configuration, tests and Docker image builds. It never publishes an image.

## The one check to mark as required

Set exactly **one** required status check on both `develop` and `main`
(Settings → Rules, or Settings → Branches → *Require status checks to pass
before merging*):

| Check name        | What it guards                                     |
| ----------------- | -------------------------------------------------- |
| `Required checks` | every validation job passed or was legitimately skipped |

Also enable *Require branches to be up to date before merging*, otherwise two
PRs that each pass individually can still break `develop` when both land.

### Why one check and not nine

Jobs only run when files they care about changed — a documentation-only PR does
not rebuild three Docker images. But a **skipped job reports no status at all**,
so requiring `Python` directly would leave every PR that does not touch Python
stuck forever on *"Expected — waiting for status to be reported"*.

`Required checks` solves this. It declares `needs:` on every other job and
`if: always()`, so it runs no matter what happened upstream, and fails only when
a dependency actually failed or was cancelled. A skipped dependency counts as
success. Its job summary prints a table of what ran and what was skipped, so the
detail is still one click away.

Do **not** add the individual job names as required checks. The moment path
filtering skips one, merges block.

## Why the `Terraform` job detects its own input

The job runs when a `*.tf` or `*.tfvars` file changed, but its first step still
checks whether any Terraform actually exists in the tree before setting up the
CLI. That covers the case where the last Terraform file in the repository is
deleted: the job runs, finds nothing, and passes instead of erroring.

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
  locally, source your own `.env`.

## Deliberately not here

Image publishing. This workflow builds images to prove the Dockerfiles are
valid and throws them away (`push: false`). Pushing to a registry belongs in a
separate workflow triggered from `develop`/`main`, not from pull requests —
a PR from a fork must never be able to publish an image.
