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

This is the standard privileged-sidecar Docker-in-Docker pattern (the
alternative, Sysbox, needs a custom node runtime/AMI and is out of scope for
this demo). The privilege is scoped to one container in one pod, in a
per-workspace namespace (`coder-ws-<owner>-<workspace>`) whose egress
NetworkPolicy only allows DNS, HTTP and HTTPS — same isolation boundary as any
other workspace on this platform.

On first boot, the startup script clones `api-python`, waits for the sidecar
to come up, then `docker build`s and runs it — the running container is
exposed as an app tab (Swagger UI at `/docs`) in the Coder dashboard.

## Quick start

```bash
cp .env.example .env   # fill in CODER_ADMIN_PASSWORD, GITHUB_TOKEN, template metadata

task up                 # push the template, provision a workspace
task logs                # tail the workspace's startup logs
```

## Commands

| Command         | Description                                              |
|-----------------|-----------------------------------------------------------|
| `task up`       | Push the template and provision a workspace               |
| `task template` | Push/update the template only                             |
| `task workspace`| Provision a workspace (`NAME=<name>` to override the name) |
| `task logs`     | Stream startup logs from the active workspace              |
| `task clean`    | Delete all workspaces and templates (Coder stays running)  |
| `task validate` | `terraform fmt`/`validate` + `shellcheck`                  |
