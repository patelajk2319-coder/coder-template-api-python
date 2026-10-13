# coder-template-api-python

Coder workspace template that provisions a developer environment for
[api-python](https://github.com/patelajk2319-coder/api-python), demonstrating
Docker-in-Docker on Coder: even inside a Kubernetes-backed, redirected
workspace, a developer can still `docker build`/`docker run` like they would
locally.

## Versioning
`task template` pushes a new Coder template revision named after whatever's currently in `VERSION`, so bump it before
pushing a new revision (pushing the same version name twice fails — Coder
requires unique template version names).

`task template` applies `terraform/coderd` (the `coderd` Terraform provider,
not the `coder` CLI) — a separate Terraform root from `templates/api-python-workspace`,
which is the workspace template's own Terraform, executed by the provisioner on
each build. `task workspace` and `task logs` still go through the `coder` CLI
directly — there's no Terraform resource for provisioning an ephemeral
workspace or streaming its logs.

## Prerequisites

Everything below describes the Coder control plane you're pushing this
template to — ask its platform team for these, then fill them into `.env`
(see `.env.example`):

- **A reachable Coder URL** (`CODER_URL`) — typically a port-forward, since
  Coder's LoadBalancer is usually internal-only.
- **Admin credentials** (`CODER_ADMIN_EMAIL`/`CODER_ADMIN_PASSWORD`) — used
  by `task workspace`/`task logs` only (`coder create` / log streaming have
  no Terraform equivalent).
- **A long-lived API token** (`CODER_API_TOKEN`) for the `coderd` Terraform
  provider (`task template`).
- **GitHub external auth configured** on the control plane
  (`CODER_EXTERNAL_AUTH_0_*`) — each developer authorizes their own GitHub
  identity from the Coder dashboard on first workspace build; no PAT is
  baked into this template.

Also needed locally: `coder`, `terraform`, `go-task`, `shellcheck`.

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
runs it against the sidecar.

**Why a bare `kubernetes_pod`, not a `kubernetes_deployment`**: the pod's
`count = data.coder_workspace.me.start_count` means Terraform's destroy (on
workspace stop) calls the Kubernetes delete API directly on that exact pod,
with no intermediate controller that could independently keep it alive. A
Deployment's own reconciler sits in between — external drift (a stuck
rollout, a manual `kubectl scale`, an HPA) can desync its replica count from
what Terraform last applied, so a workspace can show "stopped" in Coder
while its pod is still running. A workspace is also a unique, stateful,
individually-owned environment, not a fleet of interchangeable replicas —
there's nothing for a Deployment's self-healing/rolling-update machinery to
usefully do here.

**Disk usage**: `resources_monitoring` on the agent alerts in the Coder
dashboard at 90% of the 50Gi home PVC — a real ceiling, not padding; earlier
10Gi default proved too tight (real usage has hit 47-50GB).

**First build can take several minutes** if the cluster needs to schedule a
new node — Coder can only stream logs once the agent starts, so there's an
inherent gap with no visible progress before that. Restarting during this
gap doesn't help; it cancels the in-flight build and starts the wait over.

## Quick start

```bash
cp .env.example .env   # fill in CODER_ADMIN_PASSWORD, CODER_API_TOKEN, template metadata

task template            # push the template
task workspace           # provision a workspace
task logs                # tail the workspace's startup logs
```

## Local API access

This repo is for whoever owns the template — developers should never
need it.

Developers can run the following command to get connect to a workspace running this template from their local machine

```bash
coder port-forward <workspace-name> --tcp 8000:8000
```

## Commands

| Command          | Description                                                    |
|------------------|-------------------------------------------------------------------|
| `task template`  | Push/update the template via Terraform, versioned from `VERSION`   |
| `task release`   | Tag and push the current `VERSION` as a git release (`vX.Y.Z`)      |
| `task workspace` | Provision a workspace (`NAME=<name>` to override the name)          |
| `task logs`      | Stream startup logs from the active workspace                       |
| `task validate`  | `terraform fmt`/`validate` + `shellcheck`                            |
