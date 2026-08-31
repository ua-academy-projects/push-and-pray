# Security scanning

`.github/workflows/security.yml` runs static analysis and supply-chain scanning
on every pull request targeting `develop` and `main`, on pushes to `develop`,
and on a weekly schedule.

The weekly run is not redundant. New CVEs are published and new CodeQL queries
are shipped without anything in this repository changing, so code that was clean
last month can be vulnerable today with an identical diff.

## What runs

| Check | Tool | What it looks for |
| --- | --- | --- |
| `Secret scan` | gitleaks | credentials committed anywhere in git history |
| `IaC scan` | Trivy (config) | misconfigured Terraform, Dockerfiles, Compose |
| `Dependency scan` | Trivy (fs) | known CVEs in `go.sum`, `uv.lock`, `package-lock.json` |
| `CodeQL (go\|python\|javascript-typescript)` | CodeQL | injection, unsafe deserialisation, path traversal, and similar |

Python also gained static security linting inside the existing `Python` job:
`pyproject.toml` now selects ruff's `S` ruleset (flake8-bandit), which catches
hardcoded credentials, `subprocess(shell=True)`, weak hashing and similar. It
costs nothing extra in CI because ruff already runs there.

`assert` is ignored under `**/tests/**` — S101 exists because `assert`
disappears under `python -O` in production code, which does not apply to a test
suite.

## Which checks block a merge, and why

Not every finding should stop a PR. The split is deliberate:

**Blocking — `Secret scan`, but only for commits the pull request adds.** A
credential is compromised the moment it is pushed, and deleting the file does
not help, so a *new* secret must stop the merge. The full history is a separate
matter: this repository already carries findings from before it was restructured
(see below), and re-reporting them on every pull request would make the check
permanently red and therefore ignored. So a PR is scanned with
`--log-opts base..head` and blocks; `develop` and the weekly run scan everything
and report to the Security tab without failing.

**Blocking — `IaC scan`, at HIGH and CRITICAL only.** We write this Terraform
ourselves and every finding is directly fixable by us, so enforcing from the
start is cheap; retrofitting a baseline onto infrastructure that already exists
is not.

The job runs Trivy twice. Asked for SARIF, the action reports every severity and
ignores the `severity` input, because GitHub code scanning filters by level
itself — so the SARIF pass runs with `exit-code: 0` and only feeds the Security
tab. A second pass with `severity: HIGH,CRITICAL` and `exit-code: 1` decides
whether the build fails. Without that split, an informational finding fails the
build.

Today the scan reports three LOW findings, one per Dockerfile: DS-0026, "add a
HEALTHCHECK instruction". Our health checks are declared in the Compose files
rather than baked into the images, which is a legitimate choice, so these are
visible in the Security tab but do not block. The Terraform is clean.

**Reporting only — `Dependency scan`.** A CVE published upstream overnight would
otherwise block every unrelated PR the next morning, including the one fixing
it. Findings go to the Security tab and get triaged there.

**Reporting only — `CodeQL`.** Results appear as annotations on the PR and in
the Security tab. CodeQL is thorough enough to produce findings that need human
judgement rather than an automatic block.

Once the team has triaged the initial backlog, `Dependency scan` is the natural
next candidate to make blocking.

## Where to read the results

Repository → **Security** → **Code scanning**. Every tool uploads SARIF, so
findings are deduplicated, tracked across runs, and shown inline on the PR diff
rather than buried in job logs.

## Not included, deliberately

**Container image scanning.** Trivy can scan the built images for OS-level CVEs,
but that means building them a second time (the validation workflow discards
them with `load: false`). Worth adding once image builds are stable — most
findings will be base-image CVEs fixed by bumping the base image tag.

**DAST (OWASP ZAP and similar).** ZAP scans a *running* application over HTTP,
so it needs the whole stack up and healthy first. That belongs on a schedule or
against a deployed preview environment, not on every pull request.

## The existing backlog

The first full-history run found ten hits across 269 commits, all predating the
current layout (`proxy-service/`, `provision/`, `services/history-service/` no
longer exist). They are not equally serious:

**Needs action.** A real provider API key in a committed `.env`, and two private
keys under `provision/certs/`. This repository is public, so all three must be
treated as compromised regardless of whether the files still exist on any
branch: rotate the key, reissue the certificates.

**Noise.** Placeholder values in various `.env.example` files and two string
literals in an old test. gitleaks flags them on entropy alone.

Deleting the files does not help — the objects stay in the history and remain
reachable. The options are to rotate the credentials and accept the history, or
to rewrite it with `git filter-repo`, which rewrites every commit hash and
forces everyone to re-clone. Rotating is almost always the right trade.

This is tracked separately rather than in the pull request that introduced
scanning: fixing the findings and adding the tool that finds them are different
pieces of work, and the second should not wait on the first.
