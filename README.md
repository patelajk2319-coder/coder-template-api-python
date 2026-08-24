# coder-template-api-python

Coder workspace template that provisions a developer environment for
[api-python](https://github.com/patelajk2319-coder/api-python), demonstrating
Docker-in-Docker on Coder: even inside a Kubernetes-backed, redirected
workspace, a developer can still `docker build`/`docker run` like they would
locally.

This repo only pushes a template and provisions workspaces against an
already-running Coder instance — it never touches the underlying
infrastructure. That's owned by
[coder-demo-eks](https://github.com/patelajk2319-coder/coder-demo-eks) (EKS,
RDS PostgreSQL, Secrets Manager, Coder itself).

Versioned with [semantic versioning](https://semver.org/) — see `VERSION` and
the repo's git tags (`vX.Y.Z`). `task template` pushes a new Coder template
revision named after whatever's currently in `VERSION`, so bump it before
pushing a new revision (pushing the same version name twice fails — Coder
requires unique template version names).

## Prerequisites

- `coder-demo-eks` deployed (`task infra` → `task coder` → `task init`) and its
  port-forward running (`task port-forward` in that repo) — Coder's
  LoadBalancer is internal-only, so this repo talks to it over
  `http://localhost:8080`.
- `coder`, `terraform`, `go-task`, `jq` installed locally.
- A GitHub fine-grained PAT scoped to read the (private) `api-python` repo.

## How it works

Each workspace is a single Kubernetes pod with two containers:

- **workspace** — the developer's shell/IDE, non-root, with a persistent
  `/home/coder` on a `gp3` EBS-backed PVC.
- **dind** — a privileged `docker:27-dind` sidecar. Since both containers
  share the pod's network namespace, the workspace container talks to it over
  `DOCKER_HOST=tcp://localhost:2375` — no socket-mount or host Docker access
  needed.

The `dind` privilege is scoped to that one container, in a per-workspace
namespace (`coder-ws-<owner>-<workspace>`) whose egress NetworkPolicy only
allows DNS, HTTP and HTTPS — same isolation as any other workspace on this
platform.

On first boot, the startup script clones `api-python`, then `task build`s and
runs it against the sidecar, exposed as an app tab (Swagger UI at `/docs`) in
the Coder dashboard.

## Quick start

```bash
cp .env.example .env   # fill in CODER_ADMIN_PASSWORD, GITHUB_TOKEN, template metadata

task up                 # push the template, provision a workspace
task logs                # tail the workspace's startup logs
```

## Local API access

This repo is for whoever owns the template (pushing versions, provisioning
workspaces on others' behalf, governance metadata) — developers should never
need it, its `.env`, or its admin credentials just to use their own workspace.

For a developer who already has a workspace running, the workspace page in
the Coder dashboard shows a "Local API access" metadata item with the exact
command to run **from their own laptop**, using their own Coder login — no
repo access, `.env`, or admin credentials involved:

```bash
coder port-forward <workspace-name> --tcp 8000:8000
```

## Commands

| Command          | Description                                                    |
|------------------|-------------------------------------------------------------------|
| `task up`        | Push the template and provision a workspace                       |
| `task template`  | Push/update the template, versioned from `VERSION`                 |
| `task release`   | Tag and push the current `VERSION` as a git release (`vX.Y.Z`)      |
| `task workspace` | Provision a workspace (`NAME=<name>` to override the name)          |
| `task logs`      | Stream startup logs from the active workspace                       |
| `task validate`  | `terraform fmt`/`validate` + `shellcheck`                            |
