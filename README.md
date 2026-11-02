# coder-template-api-python

Coder workspace template for [api-python](https://github.com/patelajk2319-coder/api-python) — demonstrates Docker-in-Docker on Coder: `docker build`/`docker run` work inside the workspace like they would locally.

## Two Terraform Roots

| | `terraform/templates/define/` | `terraform/templates/register/` |
|---|---|---|
| Defines | The workspace itself (pod, PVC, agent) | The template resource on Coder's control plane |
| Provider | `coder` + `kubernetes` | `coderd` |
| Runs via | Coder's provisioner, on every build | You, via `task template` |

You never run `terraform apply` on `terraform/templates/define/` yourself.

## Prerequisites

- A reachable Coder URL, admin credentials, a `coderd` API token
- GitHub external auth configured on the control plane

```bash
brew install terraform coder go-task shellcheck
```

## Configuration

Copy `.env.example` to `.env` and fill in:

| Variable | Description |
|---|---|
| `CODER_URL` | Coder URL |
| `CODER_ADMIN_EMAIL` / `CODER_ADMIN_PASSWORD` | Admin login |
| `CODER_API_TOKEN` | `coderd` provider token |
| `WORKSPACE_REPO` | Repo the workspace clones |
| `PROVISIONER_TAG` | Optional — routes to an external provisioner |
| `TEMPLATE_OWNER` / `TEMPLATE_COST_CENTRE` / `TEMPLATE_TEAM` / `TEMPLATE_ENV` | Governance metadata |
| `TEMPLATE_DEFAULT_TTL` / `TEMPLATE_ACTIVITY_BUMP` | Autostop TTL / activity bump |

## How It Works

Two containers per workspace pod: **workspace** (non-root, `/home/coder`
on a `gp3` PVC) and **dind** (a privileged `docker:27-dind` sidecar,
scoped to that one container). They share the pod's network namespace,
so the workspace container reaches it over
`DOCKER_HOST=tcp://localhost:2375` — no socket mount needed. Egress is
DNS/HTTP/HTTPS only. The startup script clones `api-python` and runs
`task build` against the sidecar. First build can take minutes on a
cold node — Coder can't stream logs until the agent starts.

## Quick Start

```bash
git clone https://github.com/patelajk2319-coder/coder-template-api-python.git
cd coder-template-api-python
cp .env.example .env    # fill in values
task up                 # validate, then push the template
task workspace           # provision a workspace (first time needs GitHub auth in browser)
task logs                 # tail startup logs
```

## Local API Access

```bash
coder port-forward <workspace-name> --tcp 8000:8000
```

## Commands

| Task | Description |
|---|---|
| `task up` | Validate, then push the template |
| `task template` | Push/update the template, versioned from `VERSION` |
| `task workspace` | Provision a workspace (`NAME=<name>`) |
| `task logs` | Stream startup logs from the active workspace |
| `task validate` | `terraform fmt`/`validate` + shellcheck |
| `task release` | Tag and push `VERSION` as a git release |
