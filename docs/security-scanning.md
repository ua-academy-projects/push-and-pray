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

**Blocking — `Secret scan`.** A credential in git history is compromised the
moment it is pushed, and deleting the file does not help. There is no
"triage later" for this one.

**Blocking — `IaC scan`.** We write this Terraform ourselves and every finding
is directly fixable by us. Enforcing from the start is cheap; retrofitting a
security baseline onto infrastructure that already exists is not. Right now the
Terraform is still a scaffold, so this check passes trivially — that is exactly
the right time to turn it on.

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
